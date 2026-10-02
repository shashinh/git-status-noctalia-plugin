-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../git-status/lib/config")
local core = require("../git-status/lib/service_core")
local fake = require("./fake_noctalia")
local git = require("../git-status/lib/git")
local instances = require("../git-status/lib/instances")
local monitor = require("../git-status/lib/repo_monitor")
local t = require("./testlib")

local PATHS = { git = "git", env = "env", inotifywait = "inotifywait", kill = "kill" }
local TYPE = instances.WIDGET_TYPE
local CLEAN = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -0\0"

local function setup(widgets)
    local host = fake.new({ widgets = widgets, dirs = { ["/etc/nixos"] = true, ["/a"] = true, ["/b"] = true } })
    local svc = core.start(host, { git = git, config = config, instances = instances, monitor = monitor, paths = PATHS })
    return host, svc
end

local function count(tbl)
    local n = 0
    for _ in tbl do
        n += 1
    end
    return n
end

t.test("one monitor per distinct configured repo", function()
    local host, svc = setup({
        nixos = { type = TYPE, nixos_mode = true },
        nixos2 = { type = TYPE, nixos_mode = true },
        a = { type = TYPE, repo_path = "/a" },
        bad = { type = TYPE },
        clock = { type = "clock" },
    })
    t.eq(count(svc.monitors), 2)
    t.eq(#host.streams, 2)
    t.eq(host.last("status:/etc/nixos").state, "loading")
    t.eq(host.last("status:/a").state, "loading")
end)

t.test("no widgets means no monitors", function()
    local host, svc = setup(nil)
    t.eq(count(svc.monitors), 0)
    t.eq(#host.calls, 0)
end)

t.test("rescans start new repos and stop removed ones", function()
    local host, svc = setup({ a = { type = TYPE, repo_path = "/a" } })
    host.streams[1].onLine(monitor.WATCH_PID .. " 100")
    host.widgets = { b = { type = TYPE, repo_path = "/b" } }
    host.now += core.RESCAN_MS - 1
    svc.tick()
    t.eq(svc.monitors["/a"] ~= nil, true) -- not yet
    host.now += 1
    svc.tick()
    t.eq(svc.monitors["/a"], nil)
    t.eq(svc.monitors["/b"] ~= nil, true)
    t.eq(host.detached("100"), 1)
end)

t.test("requests are routed to the named repo only", function()
    local host = setup({ a = { type = TYPE, repo_path = "/a" }, b = { type = TYPE, repo_path = "/b" } })
    host.complete("/a", { stdout = CLEAN })
    host.complete("/b", { stdout = CLEAN })
    host.state.set(core.KEYS.refreshReq, { repo = "/b", seq = 1 })
    t.eq(host.pending("/b"), 1)
    t.eq(host.pending("/a"), 0)
    host.complete("/b", { stdout = CLEAN })
    host.state.set(core.KEYS.fetchReq, { repo = "/a", seq = 1 })
    t.eq(host.pending("fetch"), 1)
end)

t.test("a request for a repo not yet scanned triggers a rescan", function()
    local host, svc = setup({})
    host.widgets = { a = { type = TYPE, repo_path = "/a" } }
    host.state.set(core.KEYS.refreshReq, { repo = "/a", seq = 1 })
    t.eq(svc.monitors["/a"] ~= nil, true)
end)

t.test("malformed requests are ignored", function()
    local host = setup({ a = { type = TYPE, repo_path = "/a" } })
    host.state.set(core.KEYS.refreshReq, 3)
    host.state.set(core.KEYS.refreshReq, { seq = 2 })
    t.eq(host.pending("/a"), 1) -- only the startup status
end)

return nil
