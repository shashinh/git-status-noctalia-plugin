-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Watches one repository and publishes its status on noctalia.state under
-- config.statusKey(path). The service runs one monitor per distinct repo.
--
-- Refresh triggers:
--   * inotify events (debounced to one refresh per tick)
--   * a fallback poll every `poll_interval_s`
--   * a fetch every `fetch_interval_min`, followed by a refresh
--   * refresh/fetch requests routed here by the service
-- At most one status and one fetch run at a time; requests arriving while
-- one is running are coalesced into a single follow-up run.

--!strict

local M = {}

M.STATUS_TIMEOUT_MS = 15000
M.FETCH_TIMEOUT_MS = 60000

-- Printed by the watcher's shell wrapper: the inotifywait PID first (so
-- stop() can kill it; runStream has no cancel), and a marker when it exits
-- (runStream has no exit callback either).
M.WATCH_PID = "__git_status_watch_pid__"
M.WATCH_EXIT = "__git_status_watch_exit__"

-- Ignore git's object store, logs and lock files: they churn on every git
-- command without changing what status reports.
M.WATCH_EXCLUDE = [[/\.git/(objects|logs|.*\.lock$|FETCH_HEAD$)]]

export type Deps = {
    git: any,
    config: any,
    paths: { [string]: string },
}

-- `cfg` must be a configured RepoConfig; `iv` the plugin-wide intervals.
function M.new(host: any, deps: Deps, cfg: any, iv: any)
    local git, paths = deps.git, deps.paths
    local repo: string = cfg.repoPath
    local key = deps.config.statusKey(repo)

    local stopped = false
    local statusRunning, statusPending = false, false
    local fetchRunning, fetchPending = false, false
    local watchAlive, watchDirty = false, false
    local watchPid: string? = nil
    local lastPoll, lastFetch, lastWatchStart = 0, 0, -math.huge
    local fetchError: string? = nil
    local fetchedAt: number? = nil -- nowMs() of the last successful fetch
    local hasUpstream = false
    local stamp = 0

    local function publish(s: { [string]: any })
        if stopped then
            return
        end
        stamp += 1
        s.stamp = stamp
        s.repoPath = repo
        s.fetchError = fetchError
        s.fetchedAt = fetchedAt
        s.unpushed = s.unpushed or {}
        host.state.set(key, s)
    end

    local refresh -- forward declaration (the completion handler recurses)

    local function statusDone()
        statusRunning = false
        if statusPending and not stopped then
            statusPending = false
            refresh()
        end
    end

    refresh = function()
        if stopped then
            return
        end
        if statusRunning then
            statusPending = true
            return
        end
        statusRunning = true
        lastPoll = host.nowMs()
        host.runAsync(git.statusArgv(paths, repo), function(r)
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
            host.runAsync(git.unpushedArgv(paths, repo), function(l)
                finish(if l.exitCode == 0 and not l.timedOut then git.parseLog(l.stdout) else {})
            end, M.STATUS_TIMEOUT_MS)
        end, M.STATUS_TIMEOUT_MS)
    end

    local function fetch()
        if stopped or not hasUpstream then
            return
        end
        if fetchRunning then
            fetchPending = true
            return
        end
        fetchRunning = true
        lastFetch = host.nowMs()
        host.runAsync(git.fetchArgv(paths, repo), function(r)
            fetchRunning = false
            if r.exitCode ~= 0 or r.timedOut then
                fetchError = if r.timedOut then "git fetch timed out" else git.firstLine(r.stderr)
                host.log("fetch failed for " .. repo .. ": " .. tostring(fetchError))
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
        if stopped or watchAlive then
            return
        end
        lastWatchStart = host.nowMs()
        watchPid = nil
        local cmd = table.concat({
            git.shellQuote(paths.inotifywait),
            "-m -r -q -e close_write,create,delete,move",
            "--exclude", git.shellQuote(M.WATCH_EXCLUDE),
            git.shellQuote(repo),
            "2>/dev/null & echo", M.WATCH_PID, "$!; wait; echo", M.WATCH_EXIT,
        }, " ")
        watchAlive = host.runStream(cmd, function(line: string)
            if line == M.WATCH_EXIT then
                watchAlive = false
                watchPid = nil
                return
            end
            local pid = string.match(line, "^" .. M.WATCH_PID .. " (%d+)$")
            if pid then
                watchPid = pid
                if stopped then
                    -- stop() ran before the PID arrived.
                    host.runAsync({ paths.kill, pid })
                end
            elseif not stopped then
                watchDirty = true
            end
        end)
    end

    local function tick()
        if stopped then
            return
        end
        local now = host.nowMs()
        if watchDirty then
            watchDirty = false
            refresh()
        elseif now - lastPoll >= iv.pollMs then
            refresh()
        end
        -- Restart a dead watcher at most once per poll interval.
        if not watchAlive and now - lastWatchStart >= iv.pollMs then
            startWatch()
        end
        if iv.fetchMs > 0 and hasUpstream and now - lastFetch >= iv.fetchMs then
            fetch()
        end
    end

    local function requestFetch()
        if hasUpstream then
            fetch()
        else
            refresh()
        end
    end

    local function stop()
        if stopped then
            return
        end
        stopped = true
        if watchPid then
            host.runAsync({ paths.kill, watchPid })
        end
    end

    -- State outlives service restarts; replace any stale status before the
    -- first git result arrives.
    publish({ state = "loading", ahead = 0, behind = 0, files = {} })
    -- Fetch after the first status reports an upstream, not before.
    lastFetch = host.nowMs() - iv.fetchMs + 5000
    refresh()
    startWatch()

    return {
        repo = repo,
        tick = tick,
        refresh = refresh,
        fetch = requestFetch,
        stop = stop,
    }
end

return M
