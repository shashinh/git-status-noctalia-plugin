# nixos-dirty

A [Noctalia](https://github.com/noctalia-dev/noctalia) (v5+) plugin that shows,
as a single dot in the bar, whether your NixOS configuration repository has
uncommitted work, and lets you review, commit and push it from a panel.

| | |
|---|---|
| Plugin id | `shashinh/nixos-dirty` |
| Entries | bar widget `dot`, panel `panel`, service `service` |
| Plugin API | 24 (Noctalia ≥ 5.0) |
| License | GPL-3.0-or-later |

## What it shows

The dot uses colors from the active Noctalia palette, so it follows theme and
light/dark changes:

| State | Palette role |
|---|---|
| Uncommitted changes or untracked files | `error` |
| Clean, but the upstream has commits you have not pulled | `tertiary` |
| Clean (also: not configured, still checking) | `outline` |

Untracked files count as dirty on purpose: a flake cannot see files that git
does not track.

Hover for a summary (for example `3 uncommitted files · 2 behind origin/main`).
Local commits that are not pushed yet are listed in the tooltip and the panel
but do not color the dot.

## The panel

Click the dot to open it.

- **Branch line**: `branch → upstream`, ahead (↑) and behind (↓) counts, and a
  refresh button that also runs `git fetch`.
- **File list**: every changed or untracked file with a checkbox (checked by
  default), its status letter, and a button that shows its diff inline.
- **Commit**: write a message, then **Commit** (or Ctrl+Enter). Only the
  checked files are committed, even if other files are already staged.
- **Commit & Push**, and **Push** when you have unpushed commits. Both ask
  for confirmation first. Push is a plain `git push` of the current branch to
  its upstream. It never force-pushes.
- Results appear in the panel and as a desktop notification.

If the repository path is unset or unusable, the dot stays visible (even with
*Hide when clean*), and the panel explains the problem and offers
**Open settings**.

## Settings

Plugin settings (Settings → Plugins → gear on *NixOS Dirty Indicator*):

| Key | Type | Default | |
|---|---|---|---|
| `repo_path` | folder | *(none)* | Git checkout of your NixOS config. Required; `~` is expanded. |
| `poll_interval_s` | int | `30` | Fallback `git status` interval. File changes are also detected immediately via inotify. |
| `fetch_interval_min` | int | `10` | How often to `git fetch` for the *behind* state. `0` disables fetching. |

Widget setting (in the bar widget's own settings):

| Key | Type | Default | |
|---|---|---|---|
| `hide_when_clean` | bool | `false` | Hide the dot when there is nothing to commit and the branch is not behind. |

In TOML:

```toml
[plugins]
enabled = [ "shashinh/nixos-dirty" ]   # plus your other plugins

[plugin_settings."shashinh/nixos-dirty"]
repo_path = "~/system-configs"

[widget.nixos_dirty]
type = "shashinh/nixos-dirty:dot"
hide_when_clean = false
# ...and add "nixos_dirty" to a bar's start/center/end list.
```

## Installing with Nix (home-manager)

The flake exports `packages.<system>.default` and `homeModules.default`.

```nix
# flake inputs
nixos-dirty = {
  url = "github:shashinh/git-status-noctalia-plugin";
  inputs.nixpkgs.follows = "nixpkgs";
};

# home-manager configuration
{
  imports = [ inputs.nixos-dirty.homeModules.default ];
  programs.noctalia-nixos-dirty.enable = true;
}
```

The module links the plugin into `$XDG_DATA_HOME/noctalia/plugins/nixos-dirty`.
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
  `noctalia msg plugins enable shashinh/nixos-dirty`.
- `[bar.<name>] start/center/end`: if present, the widget is defined but
  not placed. Add `nixos_dirty` to that list too, or delete it.

The package pins `git`, `inotify-tools` and `coreutils` by store path. `ssh`
for fetch and push comes from your `PATH` and uses the session's
`SSH_AUTH_SOCK`. Network commands never prompt: they run with
`GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes`, and fail instead of
hanging. A key that needs unlocking must already be in your agent.

### Without Nix

Copy or symlink the `nixos-dirty/` directory into
`~/.local/share/noctalia/plugins/`. `git` and `inotifywait` are then looked up
on `PATH`. Without `inotifywait`, changes are picked up on the poll interval
only.

## Development

```sh
nix develop          # luau, git, inotify-tools
luau tests/run.luau  # unit tests (parsers, config, view, service loop)
nix flake check      # tests + syntax check of every script + manifest + package build
```

Live development: symlink the checkout into the local plugin source. Scripts
hot-reload on save. Manifest changes apply on the next config reload.

```sh
ln -s "$PWD/nixos-dirty" ~/.local/share/noctalia/plugins/nixos-dirty
noctalia msg plugins enable shashinh/nixos-dirty
```

Remove the symlink before switching to the home-manager module, which wants to
own that path.

Layout:

```
nixos-dirty/            the plugin (installed as-is)
  plugin.toml           manifest and settings schema
  service.luau          background loop: inotify + poll + fetch, publishes state
  dot.luau              bar widget
  panel.luau            review / commit / push UI
  lib/git.luau          porcelain v2 parser, argv builders (pure)
  lib/config.luau       settings → validated config (pure)
  lib/view.luau         status → dot color/tooltip (pure)
  lib/service_core.luau service logic with injected host (unit-tested)
  lib/paths.luau        executable paths, substituted by package.nix
tests/                  luau CLI tests with a fake noctalia host
package.nix             callPackage-style derivation
nix/hm-module.nix       home-manager module
```

How it works: the service is the only entry that reads git. It runs
`git --no-optional-locks status --porcelain=v2 --branch -z`, so status checks
never rewrite `.git/index` and re-trigger the watcher. It also keeps an
`inotifywait -m -r` stream on the repo, which ignores `.git/objects`, logs and
lock files. Events are debounced to at most one refresh per second. The result
is published on `noctalia.state`, where the dot and the panel watch it. The
panel runs commit and push itself (argv form only; nothing goes through a
shell), then asks the service to refresh.

## Roadmap

Not in v0, but planned:

- **Open repo in terminal/editor**: a panel button that launches
  `$TERMINAL` or your editor in the repository.
- **Rebuild after commit**: an opt-in action to run `nixos-rebuild switch`
  in a terminal after committing, since it needs sudo. Pairs well with
  [`mindnbytes/nix-status`](https://github.com/noctalia-dev/community-plugins/tree/main/nix-status),
  which shows when the running system differs from the configured one.
- **Discard changes per file**: revert a file from the panel, behind a
  confirmation.
- Pull/rebase when behind (currently: pull from a terminal).

Related: `mindnbytes/nix-status` watches *system* state (booted vs current
generation, configured vs active system, flake input updates). This plugin
watches the *repository* state. The two do not overlap and work well side by
side.

## License

Copyright (C) 2026 Shashin Halalingaiah.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).
