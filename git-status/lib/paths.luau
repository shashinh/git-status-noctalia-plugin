-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Executables used by the plugin. The Nix package substitutes the @...@
-- placeholders with store paths; an unsubstituted placeholder (a plain
-- checkout used as a dev plugin source) falls back to a PATH lookup.

local function pick(substituted: string, fallback: string): string
    if string.sub(substituted, 1, 1) == "@" then
        return fallback
    end
    return substituted
end

return {
    git = pick("@git@", "git"),
    inotifywait = pick("@inotifywait@", "inotifywait"),
    env = pick("@env@", "env"),
    kill = pick("@kill@", "kill"),
}
