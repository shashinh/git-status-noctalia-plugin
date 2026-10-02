-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Popup: list uncommitted files (each with a checkbox and an inline diff),
-- commit the checked ones, and pull (fast-forward) or push after an inline
-- confirmation. One panel serves every bar widget instance: the clicked dot
-- writes `panel_target` ({ repo, title, state, message }) before toggling,
-- and the panel shows that repo's status (published by the service under
-- config.statusKey(repo)). This entry only runs the commands the user asks
-- for, then requests a refresh for that repo.

local config = require("./lib/config.luau")
local git = require("./lib/git.luau")
local paths = require("./lib/paths.luau")
local view = require("./lib/view.luau")

local KEYS = {
    target = "panel_target",
    showing = "panel_showing",
    refreshReq = "refresh_req",
    fetchReq = "fetch_req",
}
local CMD_TIMEOUT_MS = 30000
local NETWORK_TIMEOUT_MS = 60000
local DIFF_MAX_LINES = 400
local UNPUSHED_SHOWN = 5
-- Re-render this often while open so "fetched N min ago" stays current.
local TICK_MS = 30000

local target = noctalia.state.get(KEYS.target) or {}
local status = nil
local watched = {} -- status keys with a registered watch
local unchecked = {} -- path -> true; files are checked unless listed here
local expanded = {} -- path -> true
local diffs = {} -- path -> diff text (cached while expanded)
local message = ""
local inputGen = 0 -- bumped to clear the message input (new key = new control)
local confirm = nil -- nil | "push" | "commit_push" | "pull"
local busy = nil -- nil | label of the running action
local feedback = nil -- nil | { ok = bool, text = string }

local render -- forward declaration

local function bump(key)
    local prev = noctalia.state.get(key)
    local seq = if type(prev) == "table" then (prev.seq or 0) + 1 else 1
    noctalia.state.set(key, { repo = target.repo, seq = seq })
end

local function repo()
    return target.repo
end

local function files()
    return (status and status.files) or {}
end

local function selected()
    local out = {}
    for _, f in files() do
        if not unchecked[f.path] then
            table.insert(out, f)
        end
    end
    return out
end

local function plural(n, word)
    return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

local function notifyTitle()
    return view.displayName(target.title, target.repo)
end

local function setFeedback(ok, text, notifyTitle)
    feedback = { ok = ok, text = text }
    if notifyTitle then
        if ok then
            noctalia.notify(notifyTitle, text)
        else
            noctalia.notifyError(notifyTitle, text)
        end
    end
end

local function errorText(r, fallback)
    if r.timedOut then
        return fallback .. " (timed out)"
    end
    local line = git.firstLine(r.stderr)
    if line == "" then
        line = git.firstLine(r.stdout)
    end
    return if line ~= "" then line else fallback
end

-- Actions -----------------------------------------------------------------

local function push(prefix)
    busy = "Pushing…"
    render()
    noctalia.runAsync(git.pushArgv(paths, repo()), function(r)
        busy = nil
        if r.exitCode == 0 and not r.timedOut then
            setFeedback(true, (prefix or "") .. "Pushed to " .. (status.upstream or "upstream"), notifyTitle())
        else
            setFeedback(false, (prefix or "") .. "Push failed: " .. errorText(r, "git push failed"), notifyTitle())
        end
        bump(KEYS.refreshReq)
        render()
    end, NETWORK_TIMEOUT_MS)
end

local function pull()
    local n = status.behind or 0
    busy = "Pulling…"
    feedback = nil
    render()
    noctalia.runAsync(git.pullArgv(paths, repo()), function(r)
        busy = nil
        if r.exitCode == 0 and not r.timedOut then
            setFeedback(true, "Fast-forwarded " .. plural(n, "commit") .. " from " .. (status.upstream or "upstream"), notifyTitle())
        else
            setFeedback(false, "Pull failed: " .. errorText(r, "git pull --ff-only failed"), notifyTitle())
        end
        bump(KEYS.refreshReq)
        render()
    end, NETWORK_TIMEOUT_MS)
end

local function openTerminal()
    if not noctalia.runInTerminal(git.terminalCommand(repo())) then
        setFeedback(false, "Could not open a terminal (set $TERMINAL)", nil)
        render()
    end
end

local function commit(thenPush)
    local sel = selected()
    local msg = noctalia.string.trim(message)
    if #sel == 0 or msg == "" then
        return
    end
    busy = "Committing…"
    feedback = nil
    render()
    noctalia.runAsync(git.addArgv(paths, repo(), git.addSpecs(sel)), function(r)
        if r.exitCode ~= 0 or r.timedOut then
            busy = nil
            setFeedback(false, "git add failed: " .. errorText(r, "git add failed"), notifyTitle())
            render()
            return
        end
        noctalia.runAsync(git.commitArgv(paths, repo(), msg, git.commitSpecs(sel)), function(c)
            if c.exitCode ~= 0 or c.timedOut then
                busy = nil
                setFeedback(false, "Commit failed: " .. errorText(c, "git commit failed"), notifyTitle())
                bump(KEYS.refreshReq)
                render()
                return
            end
            -- Commit succeeded: reset the form.
            message = ""
            inputGen += 1
            unchecked, expanded, diffs = {}, {}, {}
            local committed = string.format("Committed %d file%s. ", #sel, if #sel == 1 then "" else "s")
            if thenPush then
                push(committed)
            else
                busy = nil
                setFeedback(true, committed, notifyTitle())
                bump(KEYS.refreshReq)
                render()
            end
        end, CMD_TIMEOUT_MS)
    end, CMD_TIMEOUT_MS)
end

local function toggleDiff(f)
    if expanded[f.path] then
        expanded[f.path] = nil
        diffs[f.path] = nil
        render()
        return
    end
    expanded[f.path] = true
    diffs[f.path] = "Loading diff…"
    render()
    noctalia.runAsync(git.diffArgv(paths, repo(), f), function(r)
        if not expanded[f.path] then
            return
        end
        -- `diff --no-index` exits 1 when files differ.
        local ok = r.exitCode == 0 or (f.kind == "untracked" and r.exitCode == 1)
        local text
        if ok then
            text = if r.stdout ~= "" then git.truncateLines(r.stdout, DIFF_MAX_LINES) else "(no textual changes)"
        else
            text = "diff failed: " .. errorText(r, "git diff failed")
        end
        diffs[f.path] = text
        render()
    end, CMD_TIMEOUT_MS)
end

-- Views -------------------------------------------------------------------

local function codeColor(code)
    if code == "D" then
        return "error"
    elseif code == "?" or code == "A" then
        return "tertiary"
    end
    return "primary"
end

local function misconfiguredView()
    -- Either the instance has no usable path, or git says it is not a repo.
    local why = if target.state ~= "configured"
        then target.message
        else (status and status.message)
    return ui.column({ key = "view:misconfigured", gap = 12, padding = 16, align = "center", justify = "center", flexGrow = 1 }, {
        ui.glyph({ name = "alert-triangle", size = 32, color = "error" }),
        ui.label({
            text = notifyTitle() .. ": git status is misconfigured",
            fontWeight = "bold",
            textAlign = "center",
        }),
        ui.label({
            text = why or "Set the repository path (or NixOS mode) in this widget's settings.",
            color = "on_surface_variant",
            textAlign = "center",
            maxWidth = 440,
        }),
        ui.label({
            text = "Repository, title, NixOS mode and glyph are per-widget settings: middle-click the dot to open them.",
            fontSize = 12,
            color = "on_surface_variant",
            textAlign = "center",
            maxWidth = 440,
        }),
    })
end

local function headerButton(key, glyph, tip, onClick)
    return ui.button({
        key = key,
        glyph = glyph,
        variant = "ghost",
        controlSize = "sm",
        tooltip = tip,
        enabled = busy == nil,
        onClick = onClick,
    })
end

local function header()
    -- Title: the configured name, or the path when none is set (then the
    -- path is not repeated below).
    local hasTitle = type(target.title) == "string" and target.title ~= ""
    local titleRow = ui.row({ key = "title-row", gap = 4, align = "center" }, {
        ui.label({
            text = if hasTitle then target.title else (target.repo or ""),
            fontSize = 15,
            fontWeight = "bold",
            flexGrow = 1,
            maxLines = 1,
        }),
        headerButton("btn:terminal", "terminal-2", "Open a terminal here", openTerminal),
        headerButton("btn:refresh", "refresh", "Fetch and refresh", function()
            feedback = nil
            bump(KEYS.fetchReq)
            render()
        end),
    })

    local branch = status.branch or "(detached HEAD)"
    local target = if status.upstream then branch .. " → " .. status.upstream else branch .. " (no upstream)"
    local chips = {
        ui.glyph({ name = "git-branch", size = 14, color = "primary" }),
        ui.label({ text = target, flexGrow = 1, maxLines = 1 }),
    }
    if (status.ahead or 0) > 0 then
        table.insert(chips, ui.label({ text = "↑" .. status.ahead, color = "primary", fontWeight = "bold" }))
    end
    if (status.behind or 0) > 0 then
        table.insert(chips, ui.label({ text = "↓" .. status.behind, color = "tertiary", fontWeight = "bold" }))
    end

    local meta = {}
    if hasTitle and target.repo then
        table.insert(meta, target.repo)
    end
    if status.upstream then
        if status.fetchedAt then
            table.insert(meta, "fetched " .. view.ago(noctalia.nowMs() - status.fetchedAt))
        elseif (tonumber(noctalia.getConfig("fetch_interval_min")) or 0) == 0 then
            table.insert(meta, "auto-fetch off")
        else
            table.insert(meta, "not fetched yet")
        end
    end

    local rows = { titleRow, ui.row({ key = "branch-row", gap = 6, align = "center" }, chips) }
    if #meta > 0 then
        table.insert(rows, ui.label({
            key = "meta",
            text = table.concat(meta, " · "),
            fontSize = 11,
            color = "on_surface_variant",
            maxLines = 1,
        }))
    end
    if status.fetchError then
        table.insert(rows, ui.label({
            key = "fetch-error",
            text = "Fetch failed: " .. status.fetchError,
            fontSize = 11,
            color = "error",
            maxLines = 2,
        }))
    end
    return ui.column({ key = "header", gap = 3 }, rows)
end

local function fileRow(f)
    local code = git.shortCode(f)
    local name = if f.origPath then f.origPath .. " → " .. f.path else f.path
    local row = ui.row({ key = "row:" .. f.path, gap = 8, align = "center" }, {
        ui.toggle({
            key = "chk:" .. f.path,
            checked = not unchecked[f.path],
            enabled = busy == nil,
            onChange = function(v)
                unchecked[f.path] = if v == "true" then nil else true
                render()
            end,
        }),
        ui.label({ text = code, fontWeight = "bold", color = codeColor(code), width = 16, textAlign = "center" }),
        ui.label({ text = name, flexGrow = 1, maxLines = 1 }),
        ui.button({
            key = "diff:" .. f.path,
            glyph = if expanded[f.path] then "chevron-up" else "file-diff",
            variant = "ghost",
            controlSize = "sm",
            enabled = true,
            tooltip = if expanded[f.path] then "Hide diff" else "Show diff",
            onClick = function()
                toggleDiff(f)
            end,
        }),
    })
    -- Same container whether or not the diff is shown: re-parenting the row
    -- would recreate its toggle, which visibly animates off→on.
    local children = { row }
    if expanded[f.path] then
        table.insert(children, ui.column({ key = "diff-body:" .. f.path, fill = "surface_variant/0.5", radius = 6, padding = 8 }, {
            ui.markdown({ text = "```diff\n" .. (diffs[f.path] or "") .. "\n```" }),
        }))
    end
    return ui.column({ key = "item:" .. f.path, gap = 4 }, children)
end

local function fileList()
    local list = files()
    if #list == 0 then
        local text = "Working tree clean."
        if (status.behind or 0) > 0 then
            text ..= string.format(" Behind %s by %s.", status.upstream or "upstream", plural(status.behind, "commit"))
        end
        return ui.column({ key = "files-clean", flexGrow = 1, align = "center", justify = "center" }, {
            ui.glyph({ name = "circle-check", size = 28, color = "outline" }),
            ui.label({ text = text, color = "on_surface_variant", textAlign = "center", maxWidth = 440 }),
        })
    end
    local rows = {}
    for _, f in list do
        table.insert(rows, fileRow(f))
    end
    return ui.scroll({ key = "file-scroll", gap = 4, flexGrow = 1 }, rows)
end

-- "Select all" when anything is unchecked, otherwise "Select none".
local function selectAllButton(nsel, total)
    local all = nsel == total
    return ui.button({
        key = "btn:select-all",
        text = if all then "Select none" else "Select all",
        glyph = if all then "square" else "checks",
        variant = "ghost",
        controlSize = "sm",
        enabled = busy == nil,
        tooltip = string.format("%d of %d selected", nsel, total),
        onClick = function()
            unchecked = {}
            if all then
                for _, f in files() do
                    unchecked[f.path] = true
                end
            end
            render()
        end,
    })
end

local function confirmBar()
    local nsel = #selected()
    local dest = string.format("%s → %s", status.branch or "HEAD", status.upstream or "upstream")
    local text
    if confirm == "commit_push" then
        text = string.format("Commit %s and push %s?", plural(nsel, "file"), dest)
    elseif confirm == "pull" then
        text = string.format("Fast-forward %s to %s (%s)?", status.branch or "HEAD",
            status.upstream or "upstream", plural(status.behind or 0, "commit"))
    else
        text = string.format("Push %s %s?", plural(status.ahead or 0, "commit"), dest)
    end
    -- Keyed apart from the action row it replaces: the reconciler reuses
    -- controls by position, and `enabled` is only applied when present, so an
    -- unkeyed Confirm could inherit a disabled Commit button's state.
    return ui.row({ key = "confirm-row", gap = 8, align = "center", fill = "error/0.12", radius = 8, padding = 8 }, {
        ui.glyph({ name = "alert-circle", size = 16, color = "error" }),
        ui.label({ text = text, flexGrow = 1, maxLines = 2 }),
        ui.button({
            key = "btn:cancel",
            text = "Cancel",
            variant = "ghost",
            controlSize = "sm",
            enabled = true,
            onClick = function()
                confirm = nil
                render()
            end,
        }),
        ui.button({
            key = "btn:confirm",
            text = "Confirm",
            variant = "destructive",
            controlSize = "sm",
            enabled = busy == nil,
            onClick = function()
                local which = confirm
                confirm = nil
                if which == "commit_push" then
                    commit(true)
                elseif which == "pull" then
                    pull()
                else
                    feedback = nil
                    push(nil)
                end
            end,
        }),
    })
end

-- Local commits a push would send (newest first), capped for space.
local function unpushedList()
    local commits = status.unpushed or {}
    local rows = {
        ui.label({
            key = "unpushed-title",
            text = "Unpushed to " .. (status.upstream or "upstream"),
            fontSize = 11,
            color = "on_surface_variant",
        }),
    }
    for i = 1, math.min(#commits, UNPUSHED_SHOWN) do
        local c = commits[i]
        table.insert(rows, ui.row({ key = "commit:" .. c.hash, gap = 8, align = "center" }, {
            ui.label({ text = c.hash, fontSize = 12, color = "primary", fontFamily = "monospace" }),
            ui.label({ text = c.subject, fontSize = 12, flexGrow = 1, maxLines = 1 }),
        }))
    end
    local more = (status.ahead or 0) - math.min(#commits, UNPUSHED_SHOWN)
    if more > 0 then
        table.insert(rows, ui.label({ key = "unpushed-more", text = "+ " .. more .. " more", fontSize = 11, color = "on_surface_variant" }))
    end
    return ui.column({ key = "unpushed", gap = 2, fill = "surface_variant/0.4", radius = 6, padding = 8 }, rows)
end

local function commitArea()
    local nsel = #selected()
    local hasMsg = noctalia.string.trim(message) ~= ""
    local canCommit = busy == nil and nsel > 0 and hasMsg
    local canPush = busy == nil and status.upstream ~= nil
    local children = {}

    if (status.ahead or 0) > 0 then
        table.insert(children, unpushedList())
    end

    if #files() > 0 then
        table.insert(children, ui.input({
            key = "msg:" .. inputGen,
            value = message,
            placeholder = if nsel > 0 then "Commit message (Ctrl+Enter to commit)" else "Select files to commit",
            multiline = true,
            height = 72,
            enabled = busy == nil and nsel > 0,
            onChange = function(v)
                message = v
                render()
            end,
            onSubmit = function(v)
                message = v
                commit(false)
            end,
        }))
    end

    if confirm then
        table.insert(children, confirmBar())
    else
        local buttons = {}
        local statusText = busy or ""
        if #files() > 0 then
            table.insert(buttons, selectAllButton(nsel, #files()))
            if busy == nil then
                statusText = string.format("%d of %d", nsel, #files())
            end
        end
        table.insert(buttons, ui.label({
            key = "action-status",
            text = statusText,
            color = "on_surface_variant",
            fontSize = 12,
            flexGrow = 1,
        }))
        if (status.behind or 0) > 0 then
            table.insert(buttons, ui.button({
                key = "btn:pull",
                text = "Pull",
                glyph = "download",
                variant = "outline",
                enabled = canPush,
                tooltip = "Fast-forward only: never merges or rebases",
                onClick = function()
                    confirm = "pull"
                    render()
                end,
            }))
        end
        if (status.ahead or 0) > 0 then
            table.insert(buttons, ui.button({
                key = "btn:push",
                text = "Push",
                glyph = "upload",
                variant = "outline",
                enabled = canPush,
                onClick = function()
                    confirm = "push"
                    render()
                end,
            }))
        end
        if #files() > 0 then
            table.insert(buttons, ui.button({
                key = "btn:commit-push",
                text = "Commit & Push",
                glyph = "upload",
                variant = "secondary",
                enabled = canCommit and canPush,
                tooltip = if status.upstream then nil else "Branch has no upstream",
                onClick = function()
                    confirm = "commit_push"
                    render()
                end,
            }))
            table.insert(buttons, ui.button({
                key = "btn:commit",
                text = "Commit",
                glyph = "git-commit",
                variant = "primary",
                enabled = canCommit,
                onClick = function()
                    commit(false)
                end,
            }))
        end
        table.insert(children, ui.row({ key = "action-row", gap = 8, align = "center" }, buttons))
    end

    if feedback then
        table.insert(children, ui.label({
            key = "feedback",
            text = feedback.text,
            color = if feedback.ok then "primary" else "error",
            fontSize = 12,
            maxLines = 4,
        }))
    end
    return ui.column({ gap = 8 }, children)
end

render = function()
    local state = status and status.state
    local body
    if target.state ~= "configured" or state == "invalid" then
        body = misconfiguredView()
    elseif state ~= "ok" then
        body = ui.column({ key = "view:loading", flexGrow = 1, align = "center", justify = "center" }, {
            ui.label({ text = "Checking repository…", color = "on_surface_variant" }),
        })
    else
        body = ui.column({ key = "view:repo", gap = 10, flexGrow = 1 }, {
            header(),
            ui.separator({}),
            fileList(),
            ui.separator({}),
            commitArea(),
        })
    end
    panel.render(ui.column({ padding = 14, gap = 10, flexGrow = 1 }, { body }))
end

local function onStatus(value)
    status = value
    -- Drop UI state for files that no longer exist.
    local present = {}
    for _, f in files() do
        present[f.path] = true
    end
    for p in unchecked do
        if not present[p] then
            unchecked[p] = nil
        end
    end
    for p in expanded do
        if not present[p] then
            expanded[p], diffs[p] = nil, nil
        end
    end
    render()
end

-- Point the panel at whatever the clicked dot wrote to `panel_target`.
-- Watches cannot be removed, so each repo's key is watched once and the
-- handler ignores repos other than the current target.
local function retarget()
    local newTarget = noctalia.state.get(KEYS.target) or {}
    if newTarget.repo ~= target.repo then
        unchecked, expanded, diffs = {}, {}, {}
        message, inputGen, feedback = "", inputGen + 1, nil
    end
    target = newTarget
    status = nil
    if target.repo then
        local key = config.statusKey(target.repo)
        status = noctalia.state.get(key)
        if not watched[key] then
            watched[key] = true
            noctalia.state.watch(key, function(value)
                if target.repo and config.statusKey(target.repo) == key then
                    onStatus(value)
                end
            end)
        end
    end
end

function onOpen(_context)
    retarget()
    confirm = nil
    noctalia.state.set(KEYS.showing, config.targetId(target.repo, target.title))
    if target.repo then
        bump(KEYS.refreshReq)
    end
    render()
end

function onClose()
    noctalia.state.set(KEYS.showing, "")
end

retarget()
render()

noctalia.setUpdateInterval(TICK_MS)

function update()
    render()
end
