-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Reads plugin-level settings into a validated config. `host` is the
-- noctalia table (or a test fake) providing getConfig/expandPath/fileInfo.

--!strict

export type Config = {
    state: string, -- "configured" | "unconfigured" | "invalid"
    message: string?,
    repoPath: string?,
    title: string?, -- display name; nil means "show the path"
    pollMs: number,
    fetchMs: number, -- 0 disables fetching
}

local M = {}

M.NIXOS_PATH = "/etc/nixos"
M.NIXOS_TITLE = "NixOS Config"

local DEFAULT_POLL_S = 30
local DEFAULT_FETCH_MIN = 10

local function trim(v: any): string
    if type(v) ~= "string" then
        return ""
    end
    return string.match(v, "^%s*(.-)%s*$") or ""
end

local function intSetting(host: any, key: string, default: number, min: number): number
    local v = tonumber(host.getConfig(key))
    if v == nil then
        return default
    end
    return math.max(min, math.floor(v))
end

function M.load(host: any): Config
    local pollMs = intSetting(host, "poll_interval_s", DEFAULT_POLL_S, 5) * 1000
    local fetchMs = intSetting(host, "fetch_interval_min", DEFAULT_FETCH_MIN, 0) * 60 * 1000

    -- NixOS mode ignores the (hidden) title and path settings entirely.
    local nixos = host.getConfig("nixos_mode") == true
    local rawPath = if nixos then M.NIXOS_PATH else trim(host.getConfig("repo_path"))
    local title: string? = if nixos then M.NIXOS_TITLE else trim(host.getConfig("title"))
    if title == "" then
        title = nil
    end

    if rawPath == "" then
        return {
            state = "unconfigured",
            message = "No repository configured. Set the repository path in the plugin settings.",
            title = title,
            pollMs = pollMs,
            fetchMs = fetchMs,
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
            pollMs = pollMs,
            fetchMs = fetchMs,
        }
    end

    return { state = "configured", repoPath = path, title = title, pollMs = pollMs, fetchMs = fetchMs }
end

return M
