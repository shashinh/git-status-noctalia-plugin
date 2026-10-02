-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Minimal test harness for the standalone luau CLI.

local M = {}
local cases = {}

function M.test(name: string, fn: () -> ())
    table.insert(cases, { name = name, fn = fn })
end

local function show(v: any): string
    if type(v) == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

function M.eq(actual: any, expected: any, what: string?)
    if actual ~= expected then
        error(string.format("%sexpected %s, got %s", if what then what .. ": " else "", show(expected), show(actual)), 2)
    end
end

function M.deepEq(actual: any, expected: any, path: string?)
    path = path or "value"
    if type(actual) ~= "table" or type(expected) ~= "table" then
        M.eq(actual, expected, path)
        return
    end
    for k, v in expected do
        M.deepEq(actual[k], v, path .. "." .. tostring(k))
    end
    for k in actual do
        if expected[k] == nil then
            error(string.format("%s: unexpected key %s", path, tostring(k)), 2)
        end
    end
end

function M.run()
    local failed = 0
    for _, c in cases do
        local ok, err = pcall(c.fn)
        if ok then
            print("ok   " .. c.name)
        else
            failed += 1
            print("FAIL " .. c.name .. "\n     " .. tostring(err))
        end
    end
    print(string.format("%d passed, %d failed", #cases - failed, failed))
    if failed > 0 then
        error("test failures")
    end
end

return M
