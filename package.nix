# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shashin Halalingaiah
{
  lib,
  stdenvNoCC,
  git,
  inotify-tools,
  coreutils,
}:

let
  manifest = lib.importTOML ./git-status/plugin.toml;
in
stdenvNoCC.mkDerivation {
  pname = "noctalia-plugin-git-status";
  inherit (manifest) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./git-status;
  };

  dontConfigure = true;
  dontBuild = true;

  # The plugin directory is installed as-is; Noctalia loads it from any root
  # whose immediate subdirectories contain a plugin.toml.
  installPhase = ''
    runHook preInstall
    dest=$out/share/noctalia/plugins/git-status
    mkdir -p "$dest"
    cp -r git-status/. "$dest/"
    substituteInPlace "$dest/lib/paths.luau" \
      --replace-fail '@git@' '${lib.getExe git}' \
      --replace-fail '@inotifywait@' '${inotify-tools}/bin/inotifywait' \
      --replace-fail '@env@' '${coreutils}/bin/env' \
      --replace-fail '@kill@' '${coreutils}/bin/kill'
    runHook postInstall
  '';

  passthru.pluginDir = "share/noctalia/plugins/git-status";

  meta = {
    description = "Noctalia bar plugin showing git working-tree status, with commit, pull and push";
    homepage = "https://github.com/shashinh/git-status-noctalia-plugin";
    license = lib.licenses.gpl3Plus;
    # Not yet in nixpkgs' maintainer-list; add the handle here when upstreaming.
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
