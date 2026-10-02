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
  manifest = lib.importTOML ./nixos-dirty/plugin.toml;
in
stdenvNoCC.mkDerivation {
  pname = "noctalia-plugin-nixos-dirty";
  inherit (manifest) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./nixos-dirty;
  };

  dontConfigure = true;
  dontBuild = true;

  # The plugin directory is installed as-is; Noctalia loads it from any root
  # whose immediate subdirectories contain a plugin.toml.
  installPhase = ''
    runHook preInstall
    dest=$out/share/noctalia/plugins/nixos-dirty
    mkdir -p "$dest"
    cp -r nixos-dirty/. "$dest/"
    substituteInPlace "$dest/lib/paths.luau" \
      --replace-fail '@git@' '${lib.getExe git}' \
      --replace-fail '@inotifywait@' '${inotify-tools}/bin/inotifywait' \
      --replace-fail '@env@' '${coreutils}/bin/env'
    runHook postInstall
  '';

  passthru.pluginDir = "share/noctalia/plugins/nixos-dirty";

  meta = {
    description = "Noctalia bar plugin indicating uncommitted changes in a NixOS config repository";
    homepage = "https://github.com/shashinh/git-status-noctalia-plugin";
    license = lib.licenses.gpl3Plus;
    # Not yet in nixpkgs' maintainer-list; add the handle here when upstreaming.
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
