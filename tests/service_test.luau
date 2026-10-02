-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../git-status/lib/config")
local core = require("../git-status/lib/service_core")
local fake = require("./fake_noctalia")
local git = require("../git-status/lib/git")
local t = require("./testlib")

local PATHS = { git = "git", env = "env", inotifywait = "inotifywait" }
local CLEAN = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -0\0"
local DIRTY = CLEAN .. "? new.nix\0"
local NO_UPSTREAM = "# branch.oid abc\0# branch.head main\0"

local function setup(cfg: { [string]: any }?)
    local host = fake.new({
        config = cfg or { repo_path = "/repo", poll_interval_s = 30, fetch_interval_min = 10 },
        dirs = { ["/repo"] = true },
    })
    local svc = core.start(host, { git = git, config = config, paths = PATHS })
    return host, svc
end

t.test("unconfigured publishes, runs nothing, starts no watcher", function()
    local host = setup({})
    t.eq(host.last().state, "unconfigured")
    t.eq(#host.calls, 0)
    t.eq(#host.streams, 0)
end)

t.test("startup publishes loading, then the parsed status", function()
    local host = setup()
    t.eq(host.published[1].state, "loading")
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = DIRTY })
    local s = host.last()
    t.eq(s.state, "ok")
    t.eq(s.dirty, true)
    t.eq(s.repoPath, "/repo")
    t.eq(s.files[1].path, "new.nix")
end)

t.test("a failing git status marks the repo invalid", function()
    local host = setup()
    host.complete("status", { exitCode = 128, stderr = "fatal: not a git repository\n" })
    t.eq(host.last().state, "invalid")
    t.eq(host.last().message, "Not a usable git repository: fatal: not a git repository")
end)

t.test("watcher command quotes the path and reports its own exit", function()
    local host = setup()
    t.eq(#host.streams, 1)
    local cmd = host.streams[1].cmd
    t.eq(string.find(cmd, "'/repo'", 1, true) ~= nil, true)
    t.eq(string.find(cmd, core.WATCH_EXIT, 1, true) ~= nil, true)
end)

t.test("inotify events are debounced to one refresh per tick", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    for _ = 1, 5 do
        host.streams[1].onLine("/repo/ MODIFY a.nix")
    end
    t.eq(host.pending("status"), 0)
    host.now += 1000
    svc.tick()
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = DIRTY })
    host.now += 1000
    svc.tick()
    t.eq(host.pending("status"), 0)
end)

t.test("requests during a running status coalesce into one follow-up", function()
    local host = setup()
    for _ = 1, 3 do
        host.state.set(core.KEYS.refreshReq, (host.state.get(core.KEYS.refreshReq) or 0) + 1)
    end
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = CLEAN })
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = CLEAN })
    t.eq(host.pending("status"), 0)
end)

t.test("fallback poll fires after poll interval", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 29000
    svc.tick()
    t.eq(host.pending("status"), 0)
    host.now += 1000
    svc.tick()
    t.eq(host.pending("status"), 1)
end)

t.test("dead watcher restarts at most once per poll interval", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    host.streams[1].onLine(core.WATCH_EXIT)
    host.now += 1000
    svc.tick()
    t.eq(#host.streams, 1)
    host.now += 30000
    svc.tick()
    t.eq(#host.streams, 2)
end)

t.test("fetch runs shortly after startup when there is an upstream, then refreshes", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 4000
    svc.tick()
    t.eq(host.pending("fetch"), 0)
    host.now += 1000
    svc.tick()
    t.eq(host.pending("fetch"), 1)
    host.complete("fetch", {})
    t.eq(host.pending("status"), 1)
    host.complete("status", { stdout = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -2\0" })
    t.eq(host.last().behind, 2)
    t.eq(host.last().fetchError, nil)
end)

t.test("fetch failure is reported without making the repo dirty", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    host.now += 5000
    svc.tick()
    host.complete("fetch", { exitCode = 128, stderr = "ssh: connect to host github.com: Network is unreachable\n" })
    host.complete("status", { stdout = CLEAN })
    t.eq(host.last().fetchError, "ssh: connect to host github.com: Network is unreachable")
    t.eq(host.last().dirty, false)
end)

t.test("no fetch without an upstream or when disabled", function()
    local host, svc = setup()
    host.complete("status", { stdout = NO_UPSTREAM })
    host.now += 3600000
    svc.tick()
    t.eq(host.pending("fetch"), 0)

    local host2, svc2 = setup({ repo_path = "/repo", fetch_interval_min = 0 })
    host2.complete("status", { stdout = CLEAN })
    host2.now += 3600000
    svc2.tick()
    t.eq(host2.pending("fetch"), 0)
end)

t.test("fetch request from the panel fetches when an upstream exists", function()
    local host = setup()
    host.complete("status", { stdout = CLEAN })
    host.state.set(core.KEYS.fetchReq, 1)
    t.eq(host.pending("fetch"), 1)
end)


t.test("title and repo path are published with every status", function()
    local host = fake.new({ config = { repo_path = "/repo", title = "Repo" }, dirs = { ["/repo"] = true } })
    core.start(host, { git = git, config = config, paths = PATHS })
    t.eq(host.last().title, "Repo")
    host.complete("status", { stdout = CLEAN })
    t.eq(host.last().title, "Repo")
    t.eq(host.last().repoPath, "/repo")
end)

t.test("when ahead, unpushed commits are listed before publishing", function()
    local host = setup()
    local n = #host.published
    host.complete("status", { stdout = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +2 -0\0" })
    t.eq(#host.published, n) -- waits for the log
    t.eq(host.pending("log"), 1)
    host.complete("log", { stdout = "aaa111 second\nbbb222 first\n" })
    local s = host.last()
    t.eq(s.ahead, 2)
    t.eq(#s.unpushed, 2)
    t.eq(s.unpushed[1].subject, "second")
end)

t.test("a running status+log still coalesces refresh requests", function()
    local host = setup()
    host.complete("status", { stdout = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +1 -0\0" })
    host.state.set(core.KEYS.refreshReq, 1)
    t.eq(host.pending("status"), 0) -- still busy with the log
    host.complete("log", { stdout = "aaa111 x\n" })
    t.eq(host.pending("status"), 1)
end)

t.test("successful fetch records fetchedAt", function()
    local host, svc = setup()
    host.complete("status", { stdout = CLEAN })
    t.eq(host.last().fetchedAt, nil)
    host.now += 5000
    svc.tick()
    host.complete("fetch", {})
    host.complete("status", { stdout = CLEAN })
    t.eq(host.last().fetchedAt, 5000)
end)

return nil
