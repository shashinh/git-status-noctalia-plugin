-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Shashin Halalingaiah

-- Pure git helpers: porcelain v2 parsing, argv builders and text utilities.
-- No noctalia.* calls here, so the module runs under the standalone luau CLI
-- for tests. Modules do not require each other (the CLI and Noctalia resolve
-- require paths differently); callers inject what they need.

--!strict

export type FileEntry = {
    xy: string, -- two-char status, "." = unmodified ("??" for untracked)
    path: string,
    origPath: string?, -- rename/copy source
    kind: string, -- "changed" | "renamed" | "unmerged" | "untracked"
}

export type Status = {
    branch: string?, -- nil when detached
    oid: string?,
    upstream: string?,
    ahead: number,
    behind: number,
    files: { FileEntry },
}

local M = {}

-- Split `rec` into `n` space-separated fields plus the untouched remainder
-- (paths may contain spaces, so the path is always the remainder).
local function fields(rec: string, n: number): ({ string }, string)
    local out = {}
    local pos = 1
    for _ = 1, n do
        local s = string.find(rec, " ", pos, true)
        if s == nil then
            table.insert(out, string.sub(rec, pos))
            return out, ""
        end
        table.insert(out, string.sub(rec, pos, s - 1))
        pos = s + 1
    end
    return out, string.sub(rec, pos)
end

-- Parse `git status --porcelain=v2 --branch -z` output.
function M.parseStatus(out: string): Status
    local status: Status = { ahead = 0, behind = 0, files = {} }
    local recs = string.split(out, "\0")
    local i = 1
    while i <= #recs do
        local rec = recs[i]
        local tag = string.sub(rec, 1, 2)
        if tag == "# " then
            local f, rest = fields(string.sub(rec, 3), 1)
            local key = f[1]
            if key == "branch.oid" then
                status.oid = if rest ~= "(initial)" then rest else nil
            elseif key == "branch.head" then
                status.branch = if rest ~= "(detached)" then rest else nil
            elseif key == "branch.upstream" then
                status.upstream = rest
            elseif key == "branch.ab" then
                local a, b = string.match(rest, "^%+(%d+) %-(%d+)$")
                status.ahead = tonumber(a) or 0
                status.behind = tonumber(b) or 0
            end
        elseif tag == "1 " then
            local f, path = fields(string.sub(rec, 3), 7)
            table.insert(status.files, { xy = f[1], path = path, kind = "changed" })
        elseif tag == "2 " then
            local f, path = fields(string.sub(rec, 3), 8)
            -- With -z the rename source is the next NUL-separated record.
            i += 1
            table.insert(status.files, { xy = f[1], path = path, origPath = recs[i], kind = "renamed" })
        elseif tag == "u " then
            local f, path = fields(string.sub(rec, 3), 9)
            table.insert(status.files, { xy = f[1], path = path, kind = "unmerged" })
        elseif tag == "? " then
            table.insert(status.files, { xy = "??", path = string.sub(rec, 3), kind = "untracked" })
        end
        i += 1
    end
    return status
end

-- The single letter that best describes a file's change, preferring the
-- worktree side (Y) over the index side (X).
function M.shortCode(entry: FileEntry): string
    if entry.kind == "untracked" then
        return "?"
    end
    if entry.kind == "unmerged" then
        return "U"
    end
    local x, y = string.sub(entry.xy, 1, 1), string.sub(entry.xy, 2, 2)
    if y ~= "." then
        return y
    end
    return x
end

-- Paths to `git add` for the selected entries. A rename's source is left
-- out: it exists in neither the worktree nor the index, so `add` would fail
-- with "pathspec did not match".
function M.addSpecs(entries: { FileEntry }): { string }
    local out = {}
    for _, e in entries do
        table.insert(out, e.path)
    end
    return out
end

-- Paths to `git commit`. Renames contribute both sides so the removal of the
-- source is recorded in the same commit.
function M.commitSpecs(entries: { FileEntry }): { string }
    local out = {}
    for _, e in entries do
        table.insert(out, e.path)
        if e.origPath then
            table.insert(out, e.origPath)
        end
    end
    return out
end

local function concat(a: { string }, b: { string }): { string }
    local out = table.clone(a)
    for _, v in b do
        table.insert(out, v)
    end
    return out
end

-- Environment that keeps network git commands from ever prompting: no
-- credential/terminal prompts and no interactive ssh host-key questions.
local function nonInteractive(paths: { [string]: string }): { string }
    return {
        paths.env,
        "GIT_TERMINAL_PROMPT=0",
        "GIT_SSH_COMMAND=ssh -o BatchMode=yes",
    }
end

-- --no-optional-locks keeps `status` from rewriting .git/index, which would
-- otherwise feed the inotify watcher and loop.
function M.statusArgv(paths: { [string]: string }, repo: string): { string }
    return {
        paths.git, "--no-optional-locks", "-C", repo,
        "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all",
    }
end

function M.fetchArgv(paths: { [string]: string }, repo: string): { string }
    return concat(nonInteractive(paths), { paths.git, "-C", repo, "fetch", "--quiet" })
end

function M.pushArgv(paths: { [string]: string }, repo: string): { string }
    return concat(nonInteractive(paths), { paths.git, "-C", repo, "push", "--quiet" })
end

-- --literal-pathspecs: file names are passed verbatim, so a name containing
-- glob characters (`*`, `?`, `[`) or `:(magic)` never matches other files.
-- Fast-forward only: never creates a merge commit or rebases; diverged
-- histories fail with git's own message instead.
function M.pullArgv(paths: { [string]: string }, repo: string): { string }
    return concat(nonInteractive(paths), { paths.git, "-C", repo, "pull", "--ff-only", "--quiet" })
end

M.UNPUSHED_MAX = 20

-- Local commits not yet on the upstream, newest first.
function M.unpushedArgv(paths: { [string]: string }, repo: string): { string }
    return {
        paths.git, "-C", repo, "log", "--no-color", "--format=%h %s",
        "-n", tostring(M.UNPUSHED_MAX), "@{upstream}..HEAD",
    }
end

export type Commit = { hash: string, subject: string }

function M.parseLog(out: string): { Commit }
    local commits = {}
    for line in string.gmatch(out, "[^\n]+") do
        local hash, subject = string.match(line, "^(%S+) ?(.*)$")
        if hash then
            table.insert(commits, { hash = hash, subject = subject or "" })
        end
    end
    return commits
end

-- Shell command for noctalia.runInTerminal (which only takes a string):
-- an interactive shell in the repository.
function M.terminalCommand(repo: string): string
    return "cd " .. M.shellQuote(repo) .. ' && exec "${SHELL:-sh}"'
end

function M.addArgv(paths: { [string]: string }, repo: string, specs: { string }): { string }
    return concat({ paths.git, "--literal-pathspecs", "-C", repo, "add", "-A", "--" }, specs)
end

-- A commit with pathspecs records only those paths (`--only` semantics),
-- regardless of whatever else is already staged.
function M.commitArgv(paths: { [string]: string }, repo: string, message: string, specs: { string }): { string }
    return concat({ paths.git, "--literal-pathspecs", "-C", repo, "commit", "--quiet", "-m", message, "--" }, specs)
end

function M.diffArgv(paths: { [string]: string }, repo: string, entry: FileEntry): { string }
    if entry.kind == "untracked" then
        -- Exits 1 when there are differences; callers must accept that.
        return { paths.git, "-C", repo, "--no-pager", "diff", "--no-color", "--no-index", "--", "/dev/null", entry.path }
    end
    local argv = {
        paths.git, "--literal-pathspecs", "-C", repo, "--no-pager", "diff", "--no-color", "HEAD", "--", entry.path,
    }
    if entry.origPath then
        table.insert(argv, entry.origPath)
    end
    return argv
end

-- Keep at most `maxLines` lines, noting how many were dropped.
function M.truncateLines(text: string, maxLines: number): string
    local lines = string.split(text, "\n")
    if #lines <= maxLines then
        return text
    end
    local kept = table.move(lines, 1, maxLines, 1, {})
    return table.concat(kept, "\n") .. string.format("\n… %d more lines", #lines - maxLines)
end

-- POSIX single-quote a string for the one place a shell string is needed
-- (runStream accepts only a command string).
function M.shellQuote(s: string): string
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- First non-empty line of stderr/stdout, for compact error messages.
function M.firstLine(text: string?): string
    for line in string.gmatch(text or "", "[^\n]+") do
        local trimmed = string.match(line, "^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            return trimmed
        end
    end
    return ""
end

return M
