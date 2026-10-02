-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local t = require("./testlib")

require("./git_test")
require("./config_test")
require("./view_test")
require("./instances_test")
require("./repo_monitor_test")
require("./service_test")

t.run()
