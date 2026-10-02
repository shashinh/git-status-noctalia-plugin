-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../nixos-dirty/lib/config")
local fake = require("./fake_noctalia")
local t = require("./testlib")

t.test("unset or blank repo path is unconfigured", function()
    t.eq(config.load(fake.new()).state, "unconfigured")
    t.eq(config.load(fake.new({ config = { repo_path = "   " } })).state, "unconfigured")
end)

t.test("missing directory is invalid", function()
    local c = config.load(fake.new({ config = { repo_path = "~/nope" } }))
    t.eq(c.state, "invalid")
    t.eq(c.repoPath, "/home/test/nope")
end)

t.test("existing directory is configured, with ~ expanded", function()
    local c = config.load(fake.new({ config = { repo_path = " ~/cfg " }, dirs = { ["/home/test/cfg"] = true } }))
    t.eq(c.state, "configured")
    t.eq(c.repoPath, "/home/test/cfg")
end)

t.test("intervals default, convert units and clamp", function()
    local c = config.load(fake.new())
    t.eq(c.pollMs, 30000)
    t.eq(c.fetchMs, 600000)
    c = config.load(fake.new({ config = { poll_interval_s = 1, fetch_interval_min = 0 } }))
    t.eq(c.pollMs, 5000)
    t.eq(c.fetchMs, 0)
end)

return nil
