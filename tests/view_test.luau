-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local t = require("./testlib")
local view = require("../nixos-dirty/lib/view")

local function ok(extra)
    local s = { state = "ok", ahead = 0, behind = 0, files = {}, upstream = "origin/main" }
    for k, v in extra or {} do
        s[k] = v
    end
    return s
end

t.test("dirty repo uses the error role", function()
    local ind = view.indicator(ok({ files = { { path = "a" } } }))
    t.eq(ind.role, "error")
    t.eq(ind.clean, false)
    t.eq(ind.tooltip, "NixOS config: 1 uncommitted file")
end)

t.test("behind-only uses the tertiary role", function()
    local ind = view.indicator(ok({ behind = 2 }))
    t.eq(ind.role, "tertiary")
    t.eq(ind.clean, false)
    t.eq(ind.tooltip, "NixOS config: 2 behind origin/main")
end)

t.test("dirty wins over behind", function()
    t.eq(view.indicator(ok({ behind = 1, files = { { path = "a" }, { path = "b" } } })).role, "error")
end)

t.test("clean repo is inactive and hideable", function()
    local ind = view.indicator(ok())
    t.eq(ind.role, "outline")
    t.eq(view.hidden(ind, true), true)
    t.eq(view.hidden(ind, false), false)
end)

t.test("ahead-only is clean but mentioned", function()
    local ind = view.indicator(ok({ ahead = 1 }))
    t.eq(ind.clean, true)
    t.eq(ind.tooltip, "NixOS config: 1 unpushed commit")
end)

t.test("misconfigured is inactive and never hidden", function()
    for _, state in { "unconfigured", "invalid" } do
        local ind = view.indicator({ state = state })
        t.eq(ind.role, "outline")
        t.eq(ind.misconfigured, true)
        t.eq(view.hidden(ind, true), false)
    end
end)

t.test("loading or missing status is inactive", function()
    t.eq(view.indicator(nil).role, "outline")
    t.eq(view.indicator({ state = "loading" }).role, "outline")
end)

return nil
