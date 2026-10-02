-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local config = require("../git-status/lib/config")
local fake = require("./fake_noctalia")
local instances = require("../git-status/lib/instances")
local t = require("./testlib")

local TYPE = instances.WIDGET_TYPE

t.test("collect keeps only this plugin's widgets, in name order", function()
    local found = instances.collect({
        clock = { type = "clock" },
        b = { type = TYPE, repo_path = "/b" },
        a = { type = TYPE, nixos_mode = true },
        other = { type = "someone/else:dot", repo_path = "/x" },
    }, TYPE)
    t.eq(#found, 2)
    t.eq(found[1].nixos_mode, true)
    t.eq(found[2].repo_path, "/b")
end)

t.test("collect tolerates a missing widget table", function()
    t.eq(#instances.collect(nil, TYPE), 0)
end)

t.test("repoSet dedupes repos and skips unusable instances", function()
    local host = fake.new({ dirs = { ["/etc/nixos"] = true, ["/home/test/src"] = true } })
    local set = instances.repoSet({
        { type = TYPE, nixos_mode = true },
        { type = TYPE, nixos_mode = true, glyph = "x" }, -- same repo, other monitor
        { type = TYPE, repo_path = "~/src", title = "Src" },
        { type = TYPE }, -- unconfigured
        { type = TYPE, repo_path = "/missing" }, -- invalid
    }, config, host)
    local n = 0
    for _ in set do
        n += 1
    end
    t.eq(n, 2)
    t.eq(set["/etc/nixos"].nixos, true)
    t.eq(set["/home/test/src"].title, "Src")
end)

return nil
