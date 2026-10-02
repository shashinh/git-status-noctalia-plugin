-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../git-status/lib/config")
local fake = require("./fake_noctalia")
local git = require("../git-status/lib/git")
local monitor = require("../git-status/lib/repo_monitor")
local t = require("./testlib")

local PATHS = { git = "git", env = "env", inotifywait = "inotifywait", kill = "kill" }
local KEY = "status:/repo"
local CLEAN = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -0\0"
local DIRTY = CLEAN .. "? new.nix\0"
local NO_UPSTREAM = "# branch.oid abc\0# branch.head main\0"
local CFG = { state = "configured", repoPath = "/repo", nixos = false, glyph = "" }

local function setup(iv)
    local host = fake.new()
    local mon = monitor.new(host, { git = git, config = config, paths = PATHS }, CFG, iv or { pollMs = 30000, fetchMs = 600000 })
    return host, mon
end

t.test("startup publishes loading, then the parsed status", function()
    local host = setup()
    t.eq(host.published[1].key, KEY)
    t.eq(host.published[1].value.state, "loading")
    host.complete("status", { stdout = DIRTY })
    local s = host.last(KEY)
    t.eq(s.state, "ok")
    t.eq(s.dirty, true)
    t.eq(s.repoPath, "/repo")
    t.eq(s.files[1].path, "new.nix")
end)

t.test("a failing git status marks the repo invalid", function()
    local host = setup()
    host.complete("status", { exitCode = 128, stderr = "fatal: not a git repository\n" })
    t.eq(host.last(KEY).state, "invalid")
    t.eq(host.last(KEY).message, "Not a usable git repository: fatal: not a git repository")
end)

t.test("watcher command quotes the path, reports its PID and its exit", function()
    local host = setup()
    t.eq(#host.streams, 1)
    local cmd = host.streams[1].cmd
    t.eq(string.find(cmd, "'/repo'", 1, true) ~= nil, true)
    t.eq(string.find(cmd, monitor.WATCH_PID .. " $!", 1, true) ~= nil, true)
    t.eq(string.find(cmd, monitor.WATCH_EXIT, 1, true) ~= nil, true)
end)

t.test("inotify events are debounced to one refresh per tick; the PID line is not an event", function()
    local host, mon = setup()
    host.complete("status", { stdout = CLEAN })
    host.streams[1].onLine(monitor.WATCH_PID .. " 4242")
    host.now += 1000
    mon.tick()
    t.eq(host.pending("status"), 0)
    for _ = 1, 5 do
        host.streams[1].onLine("/repo/ MODIFY a.nix")
    end
    host.now += 1000
    mon.tick()
    t.eq(host.pending("status"), 1)
end)

t.test("requests during a running status coalesce into one follow-up", function()
    local host, mon = setup()
    mon.refresh()
    mon.refresh()
    mon.refresh()
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = CLEAN })
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = CLEAN })
    t.eq(host.pending("status"), 0)
end)

t.test("fallback poll fires after the poll interval", function()
    local host, mon = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 29000
    mon.tick()
    t.eq(host.pending("status"), 0)
    host.now += 1000
    mon.tick()
    t.eq(host.pending("status"), 1)
end)

t.test("dead watcher restarts at most once per poll interval", function()
    local host, mon = setup()
    host.complete("status", { stdout = CLEAN })
    host.streams[1].onLine(monitor.WATCH_EXIT)
    host.now += 1000
    mon.tick()
    t.eq(#host.streams, 1)
    host.now += 30000
    mon.tick()
    t.eq(#host.streams, 2)
end)

t.test("fetch runs shortly after startup when there is an upstream, then refreshes", function()
    local host, mon = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 4000
    mon.tick()
    t.eq(host.pending("fetch"), 0)
    host.now += 1000
    mon.tick()
    t.eq(host.pending("fetch"), 1)
    host.complete("fetch", {})
    host.complete("status", { stdout = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -2\0" })
    t.eq(host.last(KEY).behind, 2)
    t.eq(host.last(KEY).fetchedAt, 5000)
end)

t.test("fetch failure is reported without making the repo dirty", function()
    local host, mon = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 5000
    mon.tick()
    host.complete("fetch", { exitCode = 128, stderr = "ssh: connect to host github.com: Network is unreachable\n" })
    host.complete("status", { stdout = CLEAN })
    t.eq(host.last(KEY).fetchError, "ssh: connect to host github.com: Network is unreachable")
    t.eq(host.last(KEY).dirty, false)
end)

t.test("no fetch without an upstream or when disabled", function()
    local host, mon = setup()
    host.complete("status", { stdout = NO_UPSTREAM })
    host.now += 3600000
    mon.tick()
    t.eq(host.pending("fetch"), 0)
    local host2, mon2 = setup({ pollMs = 30000, fetchMs = 0 })
    host2.complete("status", { stdout = CLEAN })
    host2.now += 3600000
    mon2.tick()
    t.eq(host2.pending("fetch"), 0)
end)

t.test("when ahead, unpushed commits are listed before publishing", function()
    local host = setup()
    local n = #host.published
    host.complete("status", { stdout = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +2 -0\0" })
    t.eq(#host.published, n)
    host.complete("log", { stdout = "aaa111 second\nbbb222 first\n" })
    t.eq(#host.last(KEY).unpushed, 2)
    t.eq(host.last(KEY).unpushed[1].subject, "second")
end)

t.test("stop kills the watcher and ignores late results", function()
    local host, mon = setup()
    host.streams[1].onLine(monitor.WATCH_PID .. " 4242")
    local n = #host.published
    mon.stop()
    t.eq(host.detached("4242"), 1)
    host.complete("status", { stdout = DIRTY })
    t.eq(#host.published, n)
    host.now += 60000
    mon.tick()
    t.eq(host.pending("status"), 0)
end)

t.test("stop before the PID arrives kills it on arrival", function()
    local host, mon = setup()
    mon.stop()
    t.eq(host.detached("kill"), 0)
    host.streams[1].onLine(monitor.WATCH_PID .. " 777")
    t.eq(host.detached("777"), 1)
end)

return nil
