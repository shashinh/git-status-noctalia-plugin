-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Reads plugin-level settings into a validated config. `host` is the
-- noctalia table (or a test fake) providing getConfig/expandPath/fileInfo.

--!strict

export type Config = {
    state: string, -- "configured" | "unconfigured" | "invalid"
    message: string?,
    repoPath: string?,
    pollMs: number,
    fetchMs: number, -- 0 disables fetching
}

local M = {}

local DEFAULT_POLL_S = 30
local DEFAULT_FETCH_MIN = 10

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

    local raw = host.getConfig("repo_path")
    local trimmed = if type(raw) == "string" then string.match(raw, "^%s*(.-)%s*$") or "" else ""
    if trimmed == "" then
        return {
            state = "unconfigured",
            message = "No repository configured. Set the repository path in the plugin settings.",
            pollMs = pollMs,
            fetchMs = fetchMs,
        }
    end

    local path = host.expandPath(trimmed)
    local info = host.fileInfo(path)
    if info == nil or not info.isDir then
        return {
            state = "invalid",
            message = "Repository path is not a directory: " .. path,
            repoPath = path,
            pollMs = pollMs,
            fetchMs = fetchMs,
        }
    end

    return { state = "configured", repoPath = path, pollMs = pollMs, fetchMs = fetchMs }
end

return M
