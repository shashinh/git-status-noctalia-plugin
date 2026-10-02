-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- A scriptable stand-in for the `noctalia` host table. Async commands are
-- queued so tests decide when (and how) each one completes.

local M = {}

function M.new(opts: { [string]: any }?)
    opts = opts or {}
    local host = {
        now = 0,
        config = opts.config or {},
        dirs = opts.dirs or {},
        calls = {}, -- pending { argv, cb, timeout }
        streams = {}, -- { cmd, onLine }
        logs = {},
        published = {},
        watchers = {},
        values = {},
    }

    function host.nowMs() return host.now end
    function host.getConfig(key) return host.config[key] end
    function host.expandPath(p) return (string.gsub(p, "^~", "/home/test")) end
    function host.fileInfo(p)
        if host.dirs[p] then
            return { size = 0, mtime = 0, isDir = true }
        end
        return nil, "missing"
    end
    function host.log(msg) table.insert(host.logs, msg) end
    function host.runAsync(argv, cb, timeout)
        table.insert(host.calls, { argv = argv, cb = cb, timeout = timeout })
        return true
    end
    function host.runStream(cmd, onLine)
        table.insert(host.streams, { cmd = cmd, onLine = onLine })
        return true
    end

    host.state = {}
    function host.state.set(key, value)
        host.values[key] = value
        if key == "status" then
            table.insert(host.published, value)
        end
        for _, fn in host.watchers[key] or {} do
            fn(value)
        end
    end
    function host.state.get(key) return host.values[key] end
    function host.state.watch(key, fn)
        host.watchers[key] = host.watchers[key] or {}
        table.insert(host.watchers[key], fn)
    end

    -- Complete the oldest pending command whose argv contains `needle`.
    function host.complete(needle: string, result: { [string]: any })
        for i, c in host.calls do
            if table.find(c.argv, needle) then
                table.remove(host.calls, i)
                c.cb({
                    exitCode = result.exitCode or 0,
                    stdout = result.stdout or "",
                    stderr = result.stderr or "",
                    timedOut = result.timedOut or false,
                })
                return
            end
        end
        error("no pending command containing " .. needle)
    end

    function host.pending(needle: string): number
        local n = 0
        for _, c in host.calls do
            if table.find(c.argv, needle) then
                n += 1
            end
        end
        return n
    end

    function host.last() return host.published[#host.published] end

    return host
end

return M
