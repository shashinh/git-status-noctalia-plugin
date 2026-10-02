-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

local git = require("../git-status/lib/git")
local t = require("./testlib")

local H = "f2ad6c76f0115a6ba5b00456a849810e7ec0af20"
local PATHS = { git = "/bin/git", env = "/bin/env", inotifywait = "/bin/inotifywait" }

-- Captured from `git status --porcelain=v2 --branch -z --untracked-files=all`
-- (NULs written as "\0").
local SAMPLE = table.concat({
    "# branch.oid 97bd1c53c4c6f0a8c39b70c232697925d27ab683",
    "# branch.head master",
    "# branch.upstream origin/master",
    "# branch.ab +2 -3",
    "1 .D N... 100644 100644 000000 " .. H .. " " .. H .. " gone.nix",
    "1 .M N... 100644 100644 100644 " .. H .. " " .. H .. " keep.nix",
    "2 R. N... 100644 100644 100644 " .. H .. " " .. H .. " R100 new name.nix",
    "old.nix",
    "u UU N... 100644 100644 100644 100644 " .. H .. " " .. H .. " " .. H .. " conflict file.nix",
    "? untracked file.nix",
    "",
}, "\0")

t.test("parseStatus reads branch headers", function()
    local s = git.parseStatus(SAMPLE)
    t.eq(s.branch, "master")
    t.eq(s.upstream, "origin/master")
    t.eq(s.ahead, 2)
    t.eq(s.behind, 3)
    t.eq(s.oid, "97bd1c53c4c6f0a8c39b70c232697925d27ab683")
end)

t.test("parseStatus reads every entry kind, keeping spaces in paths", function()
    local s = git.parseStatus(SAMPLE)
    t.deepEq(s.files, {
        { xy = ".D", path = "gone.nix", kind = "changed" },
        { xy = ".M", path = "keep.nix", kind = "changed" },
        { xy = "R.", path = "new name.nix", origPath = "old.nix", kind = "renamed" },
        { xy = "UU", path = "conflict file.nix", kind = "unmerged" },
        { xy = "??", path = "untracked file.nix", kind = "untracked" },
    })
end)

t.test("parseStatus handles a clean repo without upstream", function()
    local s = git.parseStatus("# branch.oid abc\0# branch.head main\0")
    t.eq(s.branch, "main")
    t.eq(s.upstream, nil)
    t.eq(s.ahead, 0)
    t.eq(s.behind, 0)
    t.eq(#s.files, 0)
end)

t.test("parseStatus handles detached HEAD and initial commit", function()
    local s = git.parseStatus("# branch.oid (initial)\0# branch.head (detached)\0")
    t.eq(s.branch, nil)
    t.eq(s.oid, nil)
end)

t.test("shortCode prefers the worktree side", function()
    t.eq(git.shortCode({ xy = ".M", path = "a", kind = "changed" }), "M")
    t.eq(git.shortCode({ xy = "A.", path = "a", kind = "changed" }), "A")
    t.eq(git.shortCode({ xy = "MD", path = "a", kind = "changed" }), "D")
    t.eq(git.shortCode({ xy = "??", path = "a", kind = "untracked" }), "?")
    t.eq(git.shortCode({ xy = "UU", path = "a", kind = "unmerged" }), "U")
end)

t.test("commit specs include both sides of a rename, add specs only the target", function()
    local entries = {
        { xy = ".M", path = "a.nix", kind = "changed" },
        { xy = "R.", path = "b.nix", origPath = "c.nix", kind = "renamed" },
    }
    t.deepEq(git.commitSpecs(entries), { "a.nix", "b.nix", "c.nix" })
    t.deepEq(git.addSpecs(entries), { "a.nix", "b.nix" })
end)

t.test("argv builders never involve a shell", function()
    t.deepEq(git.statusArgv(PATHS, "/r"), {
        "/bin/git", "--no-optional-locks", "-C", "/r", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all",
    })
    t.deepEq(git.commitArgv(PATHS, "/r", "msg; rm -rf ~", { "a b" }), {
        "/bin/git", "--literal-pathspecs", "-C", "/r", "commit", "--quiet", "-m", "msg; rm -rf ~", "--", "a b",
    })
    t.deepEq(git.addArgv(PATHS, "/r", { "x", "*.nix" }), {
        "/bin/git", "--literal-pathspecs", "-C", "/r", "add", "-A", "--", "x", "*.nix",
    })
    local push = git.pushArgv(PATHS, "/r")
    t.eq(push[1], "/bin/env")
    t.eq(push[2], "GIT_TERMINAL_PROMPT=0")
    t.eq(push[3], "GIT_SSH_COMMAND=ssh -o BatchMode=yes")
    t.eq(table.find(push, "--force"), nil)
    t.eq(push[#push - 1], "push")
end)

t.test("diffArgv uses --no-index for untracked files", function()
    local u = git.diffArgv(PATHS, "/r", { xy = "??", path = "n.nix", kind = "untracked" })
    t.eq(table.find(u, "--no-index") ~= nil, true)
    t.eq(u[#u], "n.nix")
    local r = git.diffArgv(PATHS, "/r", { xy = "R.", path = "b", origPath = "a", kind = "renamed" })
    t.eq(r[#r - 1], "b")
    t.eq(r[#r], "a")
    t.eq(table.find(r, "HEAD") ~= nil, true)
end)

t.test("truncateLines caps long diffs", function()
    t.eq(git.truncateLines("a\nb", 5), "a\nb")
    t.eq(git.truncateLines("1\n2\n3\n4", 2), "1\n2\n… 2 more lines")
end)

t.test("shellQuote escapes single quotes", function()
    t.eq(git.shellQuote("/home/u/it's here"), "'/home/u/it'\\''s here'")
end)

t.test("firstLine skips blank lines", function()
    t.eq(git.firstLine("\n  \n  fatal: nope  \nmore"), "fatal: nope")
    t.eq(git.firstLine(nil), "")
end)


t.test("pullArgv is fast-forward only and non-interactive", function()
    local a = git.pullArgv(PATHS, "/r")
    t.eq(a[1], "/bin/env")
    t.eq(table.find(a, "--ff-only") ~= nil, true)
    t.eq(table.find(a, "--rebase"), nil)
end)

t.test("unpushedArgv compares against the upstream", function()
    local a = git.unpushedArgv(PATHS, "/r")
    t.eq(a[#a], "@{upstream}..HEAD")
end)

t.test("parseLog splits hash and subject", function()
    t.deepEq(git.parseLog("abc1234 fix: a thing\ndef5678 \n"), {
        { hash = "abc1234", subject = "fix: a thing" },
        { hash = "def5678", subject = "" },
    })
    t.deepEq(git.parseLog(""), {})
end)

t.test("terminalCommand quotes the path", function()
    t.eq(git.terminalCommand("/home/u/it's"), "cd '/home/u/it'\\''s' && exec \"${SHELL:-sh}\"")
end)

return nil
