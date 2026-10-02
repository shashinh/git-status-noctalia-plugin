# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shashin Halalingaiah
{
  description = "nixos-dirty: a Noctalia plugin indicating uncommitted changes in a NixOS config repo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./package.nix { };
      });

      homeModules.default = import ./nix/hm-module.nix self;

      checks = forAllSystems (
        pkgs:
        let
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./nixos-dirty
              ./tests
            ];
          };
          manifest = lib.importTOML ./nixos-dirty/plugin.toml;
          translations = lib.importJSON ./nixos-dirty/translations/en.json;
        in
        {
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;

          # Unit tests plus a syntax check of every script.
          luau = pkgs.runCommandLocal "nixos-dirty-luau-tests" { nativeBuildInputs = [ pkgs.luau ]; } ''
            cd ${src}
            luau tests/run.luau
            find nixos-dirty -name '*.luau' -print0 | xargs -0 luau-compile --null
            touch $out
          '';

          # Manifest/translation sanity, evaluated at check time.
          manifest =
            assert manifest.id == "shashinh/nixos-dirty";
            assert builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" manifest.version != null;
            assert lib.all (s: lib.hasAttrByPath (lib.splitString "." s.label_key) translations) (
              manifest.setting ++ lib.concatMap (w: w.setting or [ ]) manifest.widget
            );
            pkgs.runCommandLocal "nixos-dirty-manifest" { } "touch $out";
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.luau
            pkgs.git
            pkgs.inotify-tools
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
