-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Bar widget: a theme-colored dot (or the instance's chosen glyph) for the
-- repository configured on this widget instance, optionally with the file
-- count. Each instance watches its own repo; the service publishes status
-- per repo under config.statusKey(path).

local config = require("./lib/config.luau")
local view = require("./lib/view.luau")

local PANEL_ID = "shashinh/git-status:panel"
local DOT_SIZE = 10
local GLYPH_SIZE = 15

-- Settings changes rebuild the widget, so the config is read once.
local cfg = config.fromSettings(noctalia.getConfig, noctalia)
local statusKey = if cfg.repoPath then config.statusKey(cfg.repoPath) else nil
local status = if statusKey then noctalia.state.get(statusKey) else nil

local function bump(key)
    local prev = noctalia.state.get(key)
    local seq = if type(prev) == "table" then (prev.seq or 0) + 1 else 1
    noctalia.state.set(key, { repo = cfg.repoPath, seq = seq })
end

local function render()
    local ind = view.indicator(cfg, status)
    if view.hidden(ind, noctalia.getConfig("hide_when_clean") == true) then
        barWidget.setVisible(false)
        return
    end
    barWidget.setVisible(true)
    local glyph = view.glyphFor(cfg)
    local mark = if glyph
        then ui.glyph({ key = "glyph", name = glyph, size = GLYPH_SIZE, color = ind.role })
        else ui.box({ key = "dot", width = DOT_SIZE, height = DOT_SIZE, radius = DOT_SIZE / 2, fill = ind.role })
    local children = { mark }
    if noctalia.getConfig("show_count") == true and ind.count > 0 then
        table.insert(children, ui.label({ key = "count", text = tostring(ind.count), fontSize = 11, color = ind.role }))
    end
    local container = if barWidget.isVertical() then ui.column else ui.row
    barWidget.render(container({ align = "center", justify = "center", gap = 3 }, children))
    barWidget.setTooltip(ind.tooltip)
end

if statusKey then
    noctalia.state.watch(statusKey, function(value)
        status = value
        render()
    end)
end

function onClick()
    -- The panel is shared by every instance: tell it which repo to show.
    local showing = noctalia.state.get("panel_showing")
    local target = {
        repo = cfg.repoPath,
        title = cfg.title,
        state = cfg.state,
        message = cfg.message,
    }
    noctalia.state.set("panel_target", target)
    local mine = config.targetId(cfg.repoPath, cfg.title)
    if type(showing) == "string" and showing ~= "" and showing ~= mine then
        -- Open for another dot: close it, and (because a closing panel
        -- reopens on the next toggle) reopen it anchored at this dot.
        noctalia.togglePanel(PANEL_ID)
        noctalia.togglePanel(PANEL_ID)
    else
        noctalia.togglePanel(PANEL_ID)
    end
end

-- Opt-in (widget setting): right-click fetches and refreshes in place.
function onRightClick()
    if noctalia.getConfig("right_click_refresh") == true and cfg.repoPath then
        bump("fetch_req")
    end
end

render()
