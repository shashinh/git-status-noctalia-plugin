-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Maps the service's published status to what the bar dot shows.
-- Colors are palette role tokens so they follow the active theme.

--!strict

export type Indicator = {
    role: string, -- palette role for the dot
    tooltip: string,
    clean: boolean, -- nothing to act on (hideable)
    misconfigured: boolean, -- never hidden, even with hide_when_clean
}

local M = {}

M.ROLE_DIRTY = "error"
M.ROLE_BEHIND = "tertiary"
M.ROLE_INACTIVE = "outline"

local function plural(n: number, word: string): string
    return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

function M.indicator(status: any): Indicator
    local state = if type(status) == "table" then status.state else nil

    if state == "unconfigured" or state == "invalid" then
        return {
            role = M.ROLE_INACTIVE,
            tooltip = "NixOS config: misconfigured (click for details)",
            clean = false,
            misconfigured = true,
        }
    end

    if state ~= "ok" then
        return { role = M.ROLE_INACTIVE, tooltip = "NixOS config: checking…", clean = true, misconfigured = false }
    end

    local parts = {}
    local nfiles = #(status.files or {})
    local behind = status.behind or 0
    if nfiles > 0 then
        table.insert(parts, plural(nfiles, "uncommitted file"))
    end
    if behind > 0 then
        table.insert(parts, string.format("%d behind %s", behind, status.upstream or "upstream"))
    end
    if (status.ahead or 0) > 0 then
        table.insert(parts, plural(status.ahead, "unpushed commit"))
    end

    local role = M.ROLE_INACTIVE
    if nfiles > 0 then
        role = M.ROLE_DIRTY
    elseif behind > 0 then
        role = M.ROLE_BEHIND
    end

    local summary = if #parts > 0 then table.concat(parts, " · ") else "clean"
    return {
        role = role,
        tooltip = "NixOS config: " .. summary,
        clean = nfiles == 0 and behind == 0,
        misconfigured = false,
    }
end

-- Whether the dot should be hidden given the widget's hide_when_clean.
function M.hidden(ind: Indicator, hideWhenClean: boolean): boolean
    return hideWhenClean and ind.clean and not ind.misconfigured
end

return M
