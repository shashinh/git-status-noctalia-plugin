# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shashin Halalingaiah
#
# Installs the plugin into Noctalia's implicit "local" plugin source,
# $XDG_DATA_HOME/noctalia/plugins/<name>. That root is always scanned (with the
# highest precedence), so no [[plugins.source]] entry is needed. That matters:
# an explicit plugins.source array replaces Noctalia's default official and
# community sources, and TOML arrays do not merge across config files.
#
# Installing is not enabling: add "shashinh/nixos-dirty" to [plugins].enabled
# and place a `type = "shashinh/nixos-dirty:dot"` widget on a bar.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.noctalia-nixos-dirty;
in
{
  options.programs.noctalia-nixos-dirty = {
    enable = lib.mkEnableOption "the nixos-dirty Noctalia plugin";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "nixos-dirty.packages.\${system}.default";
      description = "The nixos-dirty plugin package.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.dataFile."noctalia/plugins/nixos-dirty".source = "${cfg.package}/${cfg.package.pluginDir}";
  };
}
