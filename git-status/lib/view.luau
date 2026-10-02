-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Maps a repository's published status (plus the widget instance's own
-- config) to what the bar dot shows. Colors are palette role tokens so they
-- follow the active theme.

--!strict

export type Indicator = {
    role: string, -- palette role for the dot/glyph
    tooltip: string,
    count: number, -- uncommitted files (0 when unknown)
    clean: boolean, -- nothing to act on (hideable)
    misconfigured: boolean, -- never hidden, even with hide_when_clean
}

local M = {}

M.ROLE_DIRTY = "error"
M.ROLE_BEHIND = "tertiary"
M.ROLE_INACTIVE = "outline"

-- Glyph used in NixOS mode when no glyph is chosen (Tabler has no NixOS
-- brand icon; the snowflake is the NixOS logo's shape).
M.NIXOS_GLYPH = "snowflake"

local function plural(n: number, word: string): string
    return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

-- What to call a repository: the instance title, else the last path
-- component (the full path is in the panel).
function M.displayName(title: string?, repoPath: string?): string
    if type(title) == "string" and title ~= "" then
        return title
    end
    if type(repoPath) == "string" then
        local base = string.match(repoPath, "([^/]+)/*$")
        if base then
            return base
        end
    end
    return "Git"
end

-- The Tabler glyph to draw for an instance, or nil for the plain dot.
function M.glyphFor(cfg: any): string?
    if type(cfg.glyph) == "string" and cfg.glyph ~= "" then
        return cfg.glyph
    end
    if cfg.nixos then
        return M.NIXOS_GLYPH
    end
    return nil
end

-- `cfg` is the widget instance's RepoConfig; `status` the repo's published
-- status (nil until the service reports).
function M.indicator(cfg: any, status: any): Indicator
    local name = M.displayName(cfg.title, cfg.repoPath)

    local function misconfigured(): Indicator
        return {
            role = M.ROLE_INACTIVE,
            tooltip = name .. ": misconfigured (click for details)",
            count = 0,
            clean = false,
            misconfigured = true,
        }
    end

    if cfg.state ~= "configured" then
        return misconfigured()
    end
    local state = if type(status) == "table" then status.state else nil
    if state == "invalid" then
        return misconfigured()
    end
    if state ~= "ok" then
        return { role = M.ROLE_INACTIVE, tooltip = name .. ": checking…", count = 0, clean = true, misconfigured = false }
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
        tooltip = name .. ": " .. summary,
        count = nfiles,
        clean = nfiles == 0 and behind == 0,
        misconfigured = false,
    }
end

-- Whether the dot should be hidden given the widget's hide_when_clean.
function M.hidden(ind: Indicator, hideWhenClean: boolean): boolean
    return hideWhenClean and ind.clean and not ind.misconfigured
end

-- "just now", "3 min ago", "2 h ago", "4 d ago" for a millisecond age.
function M.ago(ms: number): string
    local s = math.max(0, math.floor(ms / 1000))
    if s < 60 then
        return "just now"
    elseif s < 3600 then
        return string.format("%d min ago", s // 60)
    elseif s < 86400 then
        return string.format("%d h ago", s // 3600)
    end
    return string.format("%d d ago", s // 86400)
end

return M
