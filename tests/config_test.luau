-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../git-status/lib/config")
local fake = require("./fake_noctalia")
local t = require("./testlib")

local function get(tbl)
    return config.instanceGetter(tbl)
end

t.test("unset or blank repo path is unconfigured", function()
    local host = fake.new()
    t.eq(config.fromSettings(get({}), host).state, "unconfigured")
    t.eq(config.fromSettings(get({ repo_path = "   " }), host).state, "unconfigured")
end)

t.test("missing directory is invalid", function()
    local c = config.fromSettings(get({ repo_path = "~/nope" }), fake.new())
    t.eq(c.state, "invalid")
    t.eq(c.repoPath, "/home/test/nope")
end)

t.test("existing directory is configured, with ~ expanded", function()
    local c = config.fromSettings(get({ repo_path = " ~/cfg " }), fake.new({ dirs = { ["/home/test/cfg"] = true } }))
    t.eq(c.state, "configured")
    t.eq(c.repoPath, "/home/test/cfg")
    t.eq(c.nixos, false)
    t.eq(c.glyph, "")
end)

t.test("title is trimmed; blank means none", function()
    local host = fake.new({ dirs = { ["/home/test/cfg"] = true } })
    t.eq(config.fromSettings(get({ repo_path = "~/cfg", title = "  Dotfiles " }), host).title, "Dotfiles")
    t.eq(config.fromSettings(get({ repo_path = "~/cfg", title = "   " }), host).title, nil)
end)

t.test("glyph is trimmed and passed through", function()
    local host = fake.new({ dirs = { ["/r"] = true } })
    t.eq(config.fromSettings(get({ repo_path = "/r", glyph = " brand-git " }), host).glyph, "brand-git")
end)

t.test("nixos mode watches /etc/nixos and ignores title and path", function()
    local c = config.fromSettings(
        get({ nixos_mode = true, repo_path = "~/elsewhere", title = "Ignored" }),
        fake.new({ dirs = { ["/etc/nixos"] = true } })
    )
    t.eq(c.state, "configured")
    t.eq(c.repoPath, "/etc/nixos")
    t.eq(c.title, "NixOS Config")
    t.eq(c.nixos, true)
end)

t.test("nixos mode without /etc/nixos is invalid, keeping the title", function()
    local c = config.fromSettings(get({ nixos_mode = true }), fake.new())
    t.eq(c.state, "invalid")
    t.eq(c.title, "NixOS Config")
end)

t.test("intervals default, convert units and clamp", function()
    local iv = config.intervals(function() return nil end)
    t.eq(iv.pollMs, 30000)
    t.eq(iv.fetchMs, 600000)
    local cfg = { poll_interval_s = 1, fetch_interval_min = 0 }
    iv = config.intervals(function(k) return cfg[k] end)
    t.eq(iv.pollMs, 5000)
    t.eq(iv.fetchMs, 0)
end)

t.test("target ids and status keys", function()
    t.eq(config.targetId("/r", "x"), "/r")
    t.eq(config.targetId(nil, "x"), "unconfigured:x")
    t.eq(config.targetId(nil, nil), "unconfigured:")
    t.eq(config.statusKey("/etc/nixos"), "status:/etc/nixos")
end)

return nil
