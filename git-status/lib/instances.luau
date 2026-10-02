-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Finds this plugin's bar widget instances in the effective shell config
-- (noctalia.getSetting("widget")) and reduces them to the set of repositories
-- to watch. Pure: `config` is injected, `host` provides expandPath/fileInfo.

--!strict

local M = {}

M.WIDGET_TYPE = "shashinh/git-status:dot"

-- Instance setting tables whose type is ours, sorted by instance name so
-- results are deterministic.
function M.collect(widgets: any, widgetType: string): { { [string]: any } }
    local names = {}
    if type(widgets) == "table" then
        for name, tbl in widgets do
            if type(tbl) == "table" and tbl.type == widgetType then
                table.insert(names, name)
            end
        end
    end
    table.sort(names)
    local out = {}
    for _, name in names do
        table.insert(out, widgets[name])
    end
    return out
end

-- { [repoPath] = RepoConfig } for every configured instance. Instances that
-- point at the same repository share one entry (one watcher).
function M.repoSet(instances: { { [string]: any } }, config: any, host: any): { [string]: any }
    local set = {}
    for _, tbl in instances do
        local cfg = config.fromSettings(config.instanceGetter(tbl), host)
        if cfg.state == "configured" and set[cfg.repoPath] == nil then
            set[cfg.repoPath] = cfg
        end
    end
    return set
end

return M
