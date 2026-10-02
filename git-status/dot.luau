-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Bar widget: a single theme-colored dot, optionally with the file count.

local view = require("./lib/view.luau")

local PANEL_ID = "shashinh/git-status:panel"
local DOT_SIZE = 10

local status = noctalia.state.get("status")

local function render()
    local ind = view.indicator(status)
    if view.hidden(ind, noctalia.getConfig("hide_when_clean") == true) then
        barWidget.setVisible(false)
        return
    end
    barWidget.setVisible(true)
    local children = {
        ui.box({ key = "dot", width = DOT_SIZE, height = DOT_SIZE, radius = DOT_SIZE / 2, fill = ind.role }),
    }
    if noctalia.getConfig("show_count") == true and ind.count > 0 then
        table.insert(children, ui.label({ key = "count", text = tostring(ind.count), fontSize = 11, color = ind.role }))
    end
    local container = if barWidget.isVertical() then ui.column else ui.row
    barWidget.render(container({ align = "center", justify = "center", gap = 3 }, children))
    barWidget.setTooltip(ind.tooltip)
end

noctalia.state.watch("status", function(value)
    status = value
    render()
end)

function onClick()
    noctalia.togglePanel(PANEL_ID)
end

-- Opt-in (widget setting): right-click fetches and refreshes in place.
function onRightClick()
    if noctalia.getConfig("right_click_refresh") == true then
        noctalia.state.set("fetch_req", (noctalia.state.get("fetch_req") or 0) + 1)
    end
end

render()
