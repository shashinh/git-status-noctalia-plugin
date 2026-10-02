# git-status

A [Noctalia](https://github.com/noctalia-dev/noctalia) (v5+) plugin that shows
the state of git repositories as indicators in the bar. Each widget instance
watches its own repository and can have its own glyph. Click an indicator to
review, commit, pull and push from a panel. A built-in **NixOS configuration
monitor** mode watches `/etc/nixos`, so you notice an uncommitted system
config.

| | |
|---|---|
| Plugin id | `shashinh/git-status` |
| Entries | bar widget `dot`, panel `panel`, service `service` |
| Plugin API | 26 (Noctalia ≥ 5.0.0-beta.9) |
| License | GPL-3.0-or-later |

## What it shows

Each indicator is a dot, a snowflake in NixOS mode, or any Tabler glyph you
pick. Its color comes from the active Noctalia palette, so it follows theme
and light/dark changes:

| State | Palette role |
|---|---|
| Uncommitted changes or untracked files | `error` |
| Clean, but the upstream has commits you have not pulled | `tertiary` |
| Clean (also: not configured, still checking) | `outline` |

Untracked files count as dirty: for a Nix flake they are invisible until
added. With *Show file count*, the number of uncommitted files appears next to
the indicator. Hover for a summary, for example `NixOS Config: 3 uncommitted
files · 2 behind origin/main`. Unpushed commits are listed in the tooltip and
the panel but do not change the color.

### Several repositories

Add the widget once per repository and give each instance its own path,
title and glyph (for example `snowflake` for NixOS, `brand-git` for a
project, `notebook` for notes). One background service watches every
distinct repository. Instances pointing at the same repository, such as the
same widget on two monitors, share one watcher, and removing an instance
stops its watcher within a few seconds.

The panel is shared: it shows the repository of the indicator you clicked.
Clicking another indicator while it is open closes it and reopens it at that
indicator. Clicking the same indicator again closes it.

## The panel

- **Header**:
  - the title (or the repository path when no title is set)
  - `branch → upstream` with ahead (↑) and behind (↓) counts
  - the path and when the repo was last fetched
  - **Open a terminal here** (uses `$TERMINAL`) and **Fetch and refresh**
    buttons
- **Files**: every changed or untracked file with a checkbox (checked by
  default), its status letter, and an inline diff. **Select all / Select
  none** toggles every checkbox.
- **Commit**:
  - Write a message, then click **Commit** (or press Ctrl+Enter).
  - Only the checked files are committed, even if other files are already
    staged.
  - The message box and commit buttons are disabled while no file is
    selected.
- **Commit & Push**, plus **Push** when you have unpushed commits. Those
  commits (hash and subject) are listed above the buttons, so you see what
  will be sent.
- **Pull** appears when you are behind. It runs `git pull --ff-only`, which
  never merges or rebases: a diverged branch fails with git's message.
- Push, Commit & Push and Pull ask for confirmation first. Push never
  force-pushes.
- Results appear in the panel and as a desktop notification.

If an instance has no usable repository, its indicator stays visible (even
with *Hide when clean*), and the panel explains the problem. The repository
settings belong to the widget: middle-click the indicator to open them.

## Settings

Widget settings (per instance; middle-click the indicator, or use the bar
editor):

| Key | Type | Default | |
|---|---|---|---|
| `nixos_mode` | bool | `false` | **NixOS configuration monitor**: watch `/etc/nixos` (its symlink is followed) with the title "NixOS Config" and a snowflake glyph. Hides `title` and `repo_path`. |
| `title` | string | *(blank)* | Name for the panel header, tooltip and notifications. Blank shows the path. |
| `repo_path` | folder | *(none)* | Git checkout this indicator watches. Required unless NixOS mode is on. `~` is expanded. |
| `glyph` | glyph | *(empty)* | Tabler icon to draw instead of the dot. Empty means a dot, or `snowflake` in NixOS mode. |
| `hide_when_clean` | bool | `false` | Hide the indicator when there is nothing to commit and the branch is not behind. |
| `show_count` | bool | `false` | Show the number of uncommitted files next to the indicator. |
| `right_click_refresh` | bool | `false` | Right-click the indicator to fetch and refresh without opening the panel. |

Plugin settings (Settings → Plugins → gear on *Git Status*), shared by every
watched repository:

| Key | Type | Default | |
|---|---|---|---|
| `poll_interval_s` | int | `30` | Fallback `git status` interval. File changes are also detected immediately via inotify. |
| `fetch_interval_min` | int | `10` | How often to `git fetch` for the *behind* state. `0` disables fetching. |

In TOML:

```toml
[plugins]
enabled = [ "shashinh/git-status" ]   # plus your other plugins

[widget.nixos_config]
type = "shashinh/git-status:dot"
nixos_mode = true                     # snowflake glyph by default

[widget.project]
type = "shashinh/git-status:dot"
repo_path = "~/src/project"
title = "Project"
glyph = "brand-git"

# ...and add "nixos_config" and "project" to a bar's start/center/end list,
# or add the widgets from the bar editor in Noctalia's settings.
```

### Upgrading from 0.2

Version 0.3 moved `nixos_mode`, `title` and `repo_path` from
`[plugin_settings."shashinh/git-status"]` onto each `[widget.<name>]` table.
Move them there. Values left under plugin settings are ignored.

## Installing with Nix (home-manager)

The flake exports `packages.<system>.default` and `homeModules.default`.

```nix
# flake inputs
git-status = {
  url = "github:shashinh/git-status-noctalia-plugin";
  inputs.nixpkgs.follows = "nixpkgs";
};

# home-manager configuration
{
  imports = [ inputs.git-status.homeModules.default ];
  programs.noctalia-git-status.enable = true;
}
```

The module links the plugin into `$XDG_DATA_HOME/noctalia/plugins/git-status`.
That is Noctalia's built-in *local* plugin source, which is always scanned.
It does **not** add a `[[plugins.source]]` entry. Noctalia replaces arrays
when it merges config files, and an explicit source list replaces the default
official and community sources.

Installing is not enabling: add the id to `[plugins].enabled` and put the
widget on a bar (see above). Noctalia replaces arrays wholesale when it
merges config layers, and `~/.local/state/noctalia/settings.toml` (written by
the GUI) loads last. So two GUI-written lists can silently override your
config files:

- `[plugins] enabled`: if present, your plugin list in config is ignored.
  Delete the key, or enable from the GUI or with
  `noctalia msg plugins enable shashinh/git-status`.
- `[bar.<name>] start/center/end`: if present, the widget is defined but
  not placed. Add `git_status` to that list too, or delete it.

The package pins `git`, `inotify-tools` and `coreutils` by store path. `ssh`
for fetch, pull and push comes from your `PATH` and uses the session's
`SSH_AUTH_SOCK`. Network commands never prompt: they run with
`GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes`, and fail instead of
hanging. A key that needs unlocking must already be in your agent.

### Without Nix

Copy or symlink the `git-status/` directory into
`~/.local/share/noctalia/plugins/`. `git` and `inotifywait` are then looked up
on `PATH`. Without `inotifywait`, changes are picked up on the poll interval
only.

## Development

```sh
nix develop          # luau, git, inotify-tools
luau tests/run.luau  # unit tests (parsers, config, view, service loop)
nix flake check      # tests + syntax check of every script + manifest + package build
```

Live development: symlink the built package (or the checkout, if `git` and
`inotifywait` are on your `PATH`) into the local plugin source. Scripts
hot-reload on save. Manifest changes apply on the next config reload.

```sh
nix build && ln -sfn "$PWD/result/share/noctalia/plugins/git-status" ~/.local/share/noctalia/plugins/git-status
noctalia msg plugins enable shashinh/git-status
```

Remove the symlink before switching to the home-manager module, which wants to
own that path.

Layout:

```
git-status/             the plugin (installed as-is)
  plugin.toml           manifest and settings schema
  service.luau          background service entry
  dot.luau              bar widget (one per instance)
  panel.luau            review / commit / pull / push UI (shared)
  lib/git.luau          porcelain v2 + log parsers, argv builders (pure)
  lib/config.luau       settings → validated config, NixOS mode (pure)
  lib/instances.luau    widget instances → set of repos to watch (pure)
  lib/view.luau         status → color/tooltip/count/glyph (pure)
  lib/service_core.luau one monitor per repo; rescans, request routing
  lib/repo_monitor.luau one repo: inotify + poll + fetch, publishes state
  lib/paths.luau        executable paths, substituted by package.nix
tests/                  luau CLI tests with a fake noctalia host
package.nix             callPackage-style derivation
nix/hm-module.nix       home-manager module
```

How it works:

- **Finding repos.** The service is the only entry that reads git. Widget
  settings are not visible to a service's `getConfig`, and changing them does
  not restart the service. So every few seconds it reads the effective config
  with `noctalia.getSetting("widget")`, collects this plugin's instances, and
  runs one monitor per distinct repository.
- **Per-repo monitor.**
  - Runs `git --no-optional-locks status --porcelain=v2 --branch -z`, so
    status checks never rewrite `.git/index` and re-trigger the watcher. When
    the branch is ahead, it also lists the commits a push would send.
  - Keeps an `inotifywait -m -r` stream, which ignores `.git/objects`, logs
    and lock files. Events are debounced to at most one refresh per second.
  - The watcher's PID is reported so a removed repository's stream can be
    killed (`runStream` has no cancel).
  - Publishes the status under the state key `status:<repo path>`.
- **Dot and panel.** Each dot watches its own repository's key. The shared
  panel shows the repository the clicked dot wrote to `panel_target`. The
  panel runs commit, pull and push itself (argv form only; nothing goes
  through a shell), then asks the service to refresh that repository.

UI note for contributors: Noctalia's declarative reconciler reuses native
controls by position and applies `enabled` only when the prop is present. Give
rows and buttons a `key`, and always pass `enabled` explicitly.

## Roadmap

- **Rebuild after commit** (NixOS mode): an opt-in action to run
  `nixos-rebuild switch` in a terminal after committing. Pairs well with
  [`mindnbytes/nix-status`](https://github.com/noctalia-dev/community-plugins/tree/main/nix-status),
  which shows when the running system differs from the configured one.
- **Discard changes per file**, behind a confirmation.

Related: `mindnbytes/nix-status` watches NixOS *system* state (booted vs
current generation, configured vs active system, flake input updates). This
plugin watches *repository* state. The two complement each other.

## License

Copyright (C) 2026 Shashin Halalingaiah.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).
