-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- The background loop: the only place that reads git state. It publishes a
-- plain status table on noctalia.state for the dot and the panel.
--
-- Refresh triggers:
--   * inotify events (debounced to one refresh per update() tick)
--   * a fallback poll every `poll_interval_s`
--   * a fetch every `fetch_interval_min`, followed by a refresh
--   * request counters bumped by the panel (KEYS.refreshReq / KEYS.fetchReq)
-- At most one status and one fetch run at a time; requests arriving while
-- one is running are coalesced into a single follow-up run.

--!strict

local M = {}

M.KEYS = {
    status = "status",
    refreshReq = "refresh_req",
    fetchReq = "fetch_req",
}

M.TICK_MS = 1000
M.STATUS_TIMEOUT_MS = 15000
M.FETCH_TIMEOUT_MS = 60000

-- Printed by the watcher's shell wrapper when inotifywait exits, so the
-- service can notice a dead watcher (runStream has no exit callback).
M.WATCH_EXIT = "__git_status_watch_exit__"

-- Ignore git's object store, logs and lock files: they churn on every git
-- command without changing what status reports.
M.WATCH_EXCLUDE = [[/\.git/(objects|logs|.*\.lock$|FETCH_HEAD$)]]

export type Deps = {
    git: any,
    config: any,
    paths: { [string]: string },
}

function M.start(host: any, deps: Deps)
    local git, paths = deps.git, deps.paths
    local cfg = deps.config.load(host)

    local statusRunning, statusPending = false, false
    local fetchRunning, fetchPending = false, false
    local watchAlive, watchDirty = false, false
    local lastPoll, lastFetch, lastWatchStart = 0, 0, -math.huge
    local fetchError: string? = nil
    local fetchedAt: number? = nil -- nowMs() of the last successful fetch
    local hasUpstream = false
    local stamp = 0

    local function publish(s: { [string]: any })
        stamp += 1
        s.stamp = stamp
        s.repoPath = cfg.repoPath
        s.title = cfg.title
        s.fetchError = fetchError
        s.fetchedAt = fetchedAt
        s.unpushed = s.unpushed or {}
        host.state.set(M.KEYS.status, s)
    end

    local refresh -- forward declaration (the completion handler recurses)

    local function statusDone()
        statusRunning = false
        if statusPending then
            statusPending = false
            refresh()
        end
    end

    refresh = function()
        if cfg.state ~= "configured" then
            publish({ state = cfg.state, message = cfg.message, ahead = 0, behind = 0, files = {} })
            return
        end
        if statusRunning then
            statusPending = true
            return
        end
        statusRunning = true
        lastPoll = host.nowMs()
        host.runAsync(git.statusArgv(paths, cfg.repoPath), function(r)
            if r.exitCode ~= 0 or r.timedOut then
                hasUpstream = false
                local why = if r.timedOut then "git status timed out" else git.firstLine(r.stderr)
                publish({
                    state = "invalid",
                    message = "Not a usable git repository: " .. why,
                    ahead = 0,
                    behind = 0,
                    files = {},
                })
                statusDone()
                return
            end
            local st = git.parseStatus(r.stdout)
            hasUpstream = st.upstream ~= nil
            local function finish(unpushed)
                publish({
                    state = "ok",
                    branch = st.branch,
                    upstream = st.upstream,
                    ahead = st.ahead,
                    behind = st.behind,
                    files = st.files,
                    dirty = #st.files > 0,
                    unpushed = unpushed,
                })
                statusDone()
            end
            if st.ahead == 0 then
                finish({})
                return
            end
            -- Ahead: also list the commits a push would send.
            host.runAsync(git.unpushedArgv(paths, cfg.repoPath), function(l)
                finish(if l.exitCode == 0 and not l.timedOut then git.parseLog(l.stdout) else {})
            end, M.STATUS_TIMEOUT_MS)
        end, M.STATUS_TIMEOUT_MS)
    end

    local function fetch()
        if cfg.state ~= "configured" or not hasUpstream then
            return
        end
        if fetchRunning then
            fetchPending = true
            return
        end
        fetchRunning = true
        lastFetch = host.nowMs()
        host.runAsync(git.fetchArgv(paths, cfg.repoPath), function(r)
            fetchRunning = false
            if r.exitCode ~= 0 or r.timedOut then
                fetchError = if r.timedOut then "git fetch timed out" else git.firstLine(r.stderr)
                host.log("fetch failed: " .. tostring(fetchError))
            else
                fetchError = nil
                fetchedAt = host.nowMs()
            end
            refresh()
            if fetchPending then
                fetchPending = false
                fetch()
            end
        end, M.FETCH_TIMEOUT_MS)
    end

    local function startWatch()
        if cfg.state ~= "configured" or watchAlive then
            return
        end
        lastWatchStart = host.nowMs()
        local cmd = table.concat({
            git.shellQuote(paths.inotifywait),
            "-m -r -q -e close_write,create,delete,move",
            "--exclude", git.shellQuote(M.WATCH_EXCLUDE),
            git.shellQuote(cfg.repoPath :: string),
            "2>/dev/null; echo", M.WATCH_EXIT,
        }, " ")
        watchAlive = host.runStream(cmd, function(line: string)
            if line == M.WATCH_EXIT then
                watchAlive = false
            else
                watchDirty = true
            end
        end)
    end

    local function tick()
        local now = host.nowMs()
        if watchDirty then
            watchDirty = false
            refresh()
        elseif now - lastPoll >= cfg.pollMs then
            refresh()
        end
        -- Restart a dead watcher at most once per poll interval.
        if not watchAlive and now - lastWatchStart >= cfg.pollMs then
            startWatch()
        end
        if cfg.fetchMs > 0 and hasUpstream and now - lastFetch >= cfg.fetchMs then
            fetch()
        end
    end

    host.state.watch(M.KEYS.refreshReq, function()
        refresh()
    end)
    host.state.watch(M.KEYS.fetchReq, function()
        if hasUpstream then
            fetch()
        else
            refresh()
        end
    end)

    -- State survives service restarts; replace whatever the previous config
    -- published before the first git result arrives.
    publish({ state = if cfg.state == "configured" then "loading" else cfg.state, message = cfg.message, ahead = 0, behind = 0, files = {} })
    -- Fetch after the first status reports an upstream, not before.
    lastFetch = host.nowMs() - cfg.fetchMs + 5000
    refresh()
    startWatch()

    return {
        tick = tick,
        refresh = refresh,
        fetch = fetch,
    }
end

return M
