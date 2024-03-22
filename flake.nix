##
# flakem (Flake to Machine): Lightweight tooling for NixOS systems declared in Flakes
#
# 2023 Sirio Balmelli
##
{
  description = "flakem";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    inherit (flake-utils.lib) eachDefaultSystem;
  in
    eachDefaultSystem (system: rec {
      packages = let
        pkgs = import nixpkgs {
          inherit system;
        };
        rebuildOpts = pkgs.lib.cli.toGNUCommandLineShell {} {
          fast = true;
          use-remote-sudo = true;
          use-substitutes = true;
        };
        nixOpts = pkgs.lib.cli.toGNUCommandLineShell {} {
          max-jobs = "auto";
          cores = 0;
        };
        shellApp = name: commandLine: {
          ${name} = pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = with pkgs; [nixos-rebuild];
            text = ''
              set -x
              ${commandLine}
            '';
          };
        };
      in
        ##
        # All scripts take:
        #
        # $1      : user@machine:
        #           user@machine  : stanza given to SSH for remote access
        #           machine       : name of NixOS system declared in flake
        # ${@:2}  : nix options
        #           options passed to nix as-is
        ##
        pkgs.lib.concatMapAttrs shellApp {
          # build machine locally
          "build" = ''
            nixos-rebuild build \
              ${rebuildOpts} --flake ".?submodules=1#''${1##*@}" \
              ${nixOpts} "''${@:2}"
          '';

          # build machine remotely
          "build-there" = ''
            nixos-rebuild build \
              ${rebuildOpts} --build-host "$1" --target-host "$1" --flake ".?submodules=1#''${1##*@}" \
              ${nixOpts} "''${@:2}"
          '';

          # build machine locally, apply locally
          "switch" = ''
            nixos-rebuild switch \
              ${rebuildOpts} --flake ".?submodules=1#''${1##*@}" \
              ${nixOpts} "''${@:2}"
          '';

          # build machine locally, apply remotely
          "switch-push" = ''
            nixos-rebuild switch \
              ${rebuildOpts} --target-host "$1" --flake ".?submodules=1#''${1##*@}" \
              ${nixOpts} "''${@:2}"
          '';

          # build machine remotely, apply remotely
          "switch-pull" = ''
            nixos-rebuild switch \
              ${rebuildOpts} --build-host "$1" --target-host "$1" --flake ".?submodules=1#''${1##*@}" \
              ${nixOpts} "''${@:2}"
          '';
        };
    });
}
