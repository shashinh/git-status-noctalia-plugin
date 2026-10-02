-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Headless entry: wires the real host into lib/service_core.luau, which
-- watches every repository configured on this plugin's bar widgets.
-- No onConfigChanged(): a plugin-setting change (the intervals) restarts
-- this runtime, which also kills the old inotify streams.

local core = require("./lib/service_core.luau")

local runtime = core.start(noctalia, {
    git = require("./lib/git.luau"),
    config = require("./lib/config.luau"),
    instances = require("./lib/instances.luau"),
    monitor = require("./lib/repo_monitor.luau"),
    paths = require("./lib/paths.luau"),
})

noctalia.setUpdateInterval(core.TICK_MS)

function update()
    runtime.tick()
end
