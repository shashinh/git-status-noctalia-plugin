# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shashin Halalingaiah
#
# Installs the plugin into Noctalia's implicit "local" plugin source,
# $XDG_DATA_HOME/noctalia/plugins/<name>. That root is always scanned (with the
# highest precedence), so no [[plugins.source]] entry is needed. That matters:
# an explicit plugins.source array replaces Noctalia's default official and
# community sources, and TOML arrays do not merge across config files.
#
# Installing is not enabling: add "shashinh/git-status" to [plugins].enabled
# and place a `type = "shashinh/git-status:dot"` widget on a bar.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.noctalia-git-status;
in
{
  options.programs.noctalia-git-status = {
    enable = lib.mkEnableOption "the git-status Noctalia plugin";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "git-status.packages.\${system}.default";
      description = "The git-status plugin package.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.dataFile."noctalia/plugins/git-status".source = "${cfg.package}/${cfg.package.pluginDir}";
  };
}
