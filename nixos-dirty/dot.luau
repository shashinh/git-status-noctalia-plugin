-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Bar widget: a single theme-colored dot.

local view = require("./lib/view.luau")

local PANEL_ID = "shashinh/nixos-dirty:panel"
local DOT_SIZE = 10

local status = noctalia.state.get("status")

local function render()
    local ind = view.indicator(status)
    if view.hidden(ind, noctalia.getConfig("hide_when_clean") == true) then
        barWidget.setVisible(false)
        return
    end
    barWidget.setVisible(true)
    local container = if barWidget.isVertical() then ui.column else ui.row
    barWidget.render(container({ align = "center", justify = "center" }, {
        ui.box({ width = DOT_SIZE, height = DOT_SIZE, radius = DOT_SIZE / 2, fill = ind.role }),
    }))
    barWidget.setTooltip(ind.tooltip)
end

noctalia.state.watch("status", function(value)
    status = value
    render()
end)

function onClick()
    noctalia.togglePanel(PANEL_ID)
end

render()
