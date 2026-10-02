-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- The background service: runs one repo monitor per distinct repository
-- configured on this plugin's bar widget instances.
--
-- Widget settings are invisible to a service's getConfig, and changing them
-- does not restart the service, so it re-reads the instance list from the
-- effective shell config (getSetting("widget")) every RESCAN_MS and starts or
-- stops monitors to match. Refresh/fetch requests from the dot and the panel
-- arrive as { repo = path, seq = n } and are routed to that repo's monitor.

--!strict

local M = {}

M.KEYS = {
    refreshReq = "refresh_req",
    fetchReq = "fetch_req",
}

M.TICK_MS = 1000
M.RESCAN_MS = 5000

export type Deps = {
    git: any,
    config: any,
    instances: any,
    monitor: any,
    paths: { [string]: string },
}

function M.start(host: any, deps: Deps)
    local iv = deps.config.intervals(host.getConfig)
    local monitors: { [string]: any } = {}
    local lastScan = -math.huge

    local function readWidgets(): any
        local ok, widgets = pcall(host.getSetting, "widget")
        return if ok then widgets else nil
    end

    local function rescan()
        lastScan = host.nowMs()
        local found = deps.instances.collect(readWidgets(), deps.instances.WIDGET_TYPE)
        local wanted = deps.instances.repoSet(found, deps.config, host)
        for path, mon in monitors do
            if wanted[path] == nil then
                mon.stop()
                monitors[path] = nil
            end
        end
        for path, cfg in wanted do
            if monitors[path] == nil then
                monitors[path] = deps.monitor.new(host, deps, cfg, iv)
            end
        end
    end

    local function route(req: any, action: string)
        if type(req) ~= "table" or type(req.repo) ~= "string" then
            return
        end
        local mon = monitors[req.repo]
        if mon == nil then
            -- A dot can be configured before the next rescan picks it up.
            rescan()
            mon = monitors[req.repo]
        end
        if mon then
            mon[action]()
        end
    end

    local function tick()
        if host.nowMs() - lastScan >= M.RESCAN_MS then
            rescan()
        end
        for _, mon in monitors do
            mon.tick()
        end
    end

    host.state.watch(M.KEYS.refreshReq, function(req)
        route(req, "refresh")
    end)
    host.state.watch(M.KEYS.fetchReq, function(req)
        route(req, "fetch")
    end)

    rescan()

    return {
        tick = tick,
        rescan = rescan,
        monitors = monitors,
    }
end

return M
