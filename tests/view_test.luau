-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local t = require("./testlib")
local view = require("../git-status/lib/view")

local CFG = { state = "configured", repoPath = "/home/u/src/project", nixos = false, glyph = "" }

local function ok(extra)
    local s = { state = "ok", ahead = 0, behind = 0, files = {}, upstream = "origin/main" }
    for k, v in extra or {} do
        s[k] = v
    end
    return s
end

t.test("dirty repo uses the error role", function()
    local ind = view.indicator(CFG, ok({ files = { { path = "a" } } }))
    t.eq(ind.role, "error")
    t.eq(ind.clean, false)
    t.eq(ind.count, 1)
    t.eq(ind.tooltip, "project: 1 uncommitted file")
end)

t.test("behind-only uses the tertiary role", function()
    local ind = view.indicator(CFG, ok({ behind = 2 }))
    t.eq(ind.role, "tertiary")
    t.eq(ind.tooltip, "project: 2 behind origin/main")
end)

t.test("dirty wins over behind", function()
    t.eq(view.indicator(CFG, ok({ behind = 1, files = { { path = "a" } } })).role, "error")
end)

t.test("clean repo is inactive and hideable", function()
    local ind = view.indicator(CFG, ok())
    t.eq(ind.role, "outline")
    t.eq(view.hidden(ind, true), true)
    t.eq(view.hidden(ind, false), false)
end)

t.test("ahead-only is clean but mentioned", function()
    local ind = view.indicator(CFG, ok({ ahead = 1 }))
    t.eq(ind.clean, true)
    t.eq(ind.tooltip, "project: 1 unpushed commit")
end)

t.test("instance title names the tooltip", function()
    local cfg = table.clone(CFG)
    cfg.title = "Dots"
    t.eq(view.indicator(cfg, ok({ files = { { path = "a" } } })).tooltip, "Dots: 1 uncommitted file")
end)

t.test("unusable instance config or git failure is misconfigured and never hidden", function()
    local bad = { state = "unconfigured", nixos = false, glyph = "" }
    local ind = view.indicator(bad, nil)
    t.eq(ind.misconfigured, true)
    t.eq(view.hidden(ind, true), false)
    t.eq(ind.tooltip, "Git: misconfigured (click for details)")
    t.eq(view.indicator(CFG, { state = "invalid" }).misconfigured, true)
end)

t.test("no status yet is inactive and checking", function()
    local ind = view.indicator(CFG, nil)
    t.eq(ind.role, "outline")
    t.eq(ind.tooltip, "project: checking…")
end)

t.test("glyphFor: dot by default, snowflake in NixOS mode, explicit wins", function()
    t.eq(view.glyphFor({ glyph = "", nixos = false }), nil)
    t.eq(view.glyphFor({ glyph = "", nixos = true }), "snowflake")
    t.eq(view.glyphFor({ glyph = "brand-git", nixos = true }), "brand-git")
    t.eq(view.glyphFor({ glyph = "folder", nixos = false }), "folder")
end)

t.test("displayName falls back to the folder name, then Git", function()
    t.eq(view.displayName("T", "/a/b"), "T")
    t.eq(view.displayName(nil, "/a/b/"), "b")
    t.eq(view.displayName("", nil), "Git")
end)

t.test("ago formats coarse ages", function()
    t.eq(view.ago(5000), "just now")
    t.eq(view.ago(3 * 60000), "3 min ago")
    t.eq(view.ago(2 * 3600000 + 5), "2 h ago")
    t.eq(view.ago(3 * 86400000), "3 d ago")
end)

return nil
