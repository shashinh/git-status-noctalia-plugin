-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Turns settings into validated configs. Repository settings live on each
-- bar widget instance; the poll/fetch intervals are plugin-wide.
--
-- `get` is any key -> value lookup: the widget passes noctalia.getConfig,
-- the service a lookup into an instance table from getSetting("widget").
-- `host` provides expandPath/fileInfo (noctalia, or a test fake).

--!strict

export type RepoConfig = {
    state: string, -- "configured" | "unconfigured" | "invalid"
    message: string?,
    repoPath: string?,
    title: string?, -- display name; nil means "show the path"
    nixos: boolean,
    glyph: string, -- "" = auto (dot, or snowflake in NixOS mode)
}

export type Intervals = {
    pollMs: number,
    fetchMs: number, -- 0 disables fetching
}

local M = {}

M.NIXOS_PATH = "/etc/nixos"
M.NIXOS_TITLE = "NixOS Config"

-- Defaults for widget-instance keys, which getSetting omits when unset.
M.INSTANCE_DEFAULTS = {
    nixos_mode = false,
    title = "",
    repo_path = "",
    glyph = "",
}

local DEFAULT_POLL_S = 30
local DEFAULT_FETCH_MIN = 10

local function trim(v: any): string
    if type(v) ~= "string" then
        return ""
    end
    return string.match(v, "^%s*(.-)%s*$") or ""
end

local function intSetting(get: (string) -> any, key: string, default: number, min: number): number
    local v = tonumber(get(key))
    if v == nil then
        return default
    end
    return math.max(min, math.floor(v))
end

function M.intervals(get: (string) -> any): Intervals
    return {
        pollMs = intSetting(get, "poll_interval_s", DEFAULT_POLL_S, 5) * 1000,
        fetchMs = intSetting(get, "fetch_interval_min", DEFAULT_FETCH_MIN, 0) * 60 * 1000,
    }
end

function M.fromSettings(get: (string) -> any, host: any): RepoConfig
    -- NixOS mode ignores the (hidden) title and path settings entirely.
    local nixos = get("nixos_mode") == true
    local rawPath = if nixos then M.NIXOS_PATH else trim(get("repo_path"))
    local title: string? = if nixos then M.NIXOS_TITLE else trim(get("title"))
    if title == "" then
        title = nil
    end
    local glyph = trim(get("glyph"))

    if rawPath == "" then
        return {
            state = "unconfigured",
            message = "No repository configured. Set the repository path (or NixOS mode) in this widget's settings.",
            title = title,
            nixos = nixos,
            glyph = glyph,
        }
    end

    local path = host.expandPath(rawPath)
    local info = host.fileInfo(path)
    if info == nil or not info.isDir then
        return {
            state = "invalid",
            message = "Repository path is not a directory: " .. path,
            repoPath = path,
            title = title,
            nixos = nixos,
            glyph = glyph,
        }
    end

    return { state = "configured", repoPath = path, title = title, nixos = nixos, glyph = glyph }
end

-- Lookup into a raw instance table (from getSetting), applying defaults.
function M.instanceGetter(tbl: { [string]: any }): (string) -> any
    return function(key: string): any
        local v = tbl[key]
        if v == nil then
            return M.INSTANCE_DEFAULTS[key]
        end
        return v
    end
end

-- Identity of a panel target (what `panel_showing` holds): the repo path,
-- or a placeholder for an instance without a usable path.
function M.targetId(repoPath: string?, title: string?): string
    return repoPath or ("unconfigured:" .. (title or ""))
end

-- The state key a repository's status is published under.
function M.statusKey(path: string): string
    return "status:" .. path
end

return M
