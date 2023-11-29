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
      in {
        ##
        # "build here"
        #
        # Build '$1' locally.
        # Really just a shortcut to not have to remember
        # "nixosConfigurations.MACHINE.config.system.build.toplevel"
        ##
        here = pkgs.writeShellApplication {
          name = "here";
          runtimeInputs = with pkgs; [
            nix
          ];
          text = ''
            nix build --show-trace .#nixosConfigurations."$1".config.system.build.toplevel
          '';
        };

        ##
        # "they pull"
        #
        # Build '$1' on '$1' remote;
        # switch '$1' to built configuration;
        # collect garbage older than 15 days.
        #
        # $1: host name (or ssh alias) *and* nixosSystem name
        ##
        pull = pkgs.writeShellApplication {
          name = "pull";
          runtimeInputs = with pkgs; [
            nixos-rebuild
          ];
          text = builtins.readFile ./scripts/deploy.sh;
        };

        ##
        # "we push"
        #
        # Build '$1' locally;
        # switch '$1' to built configuration;
        # collect garbage older than 15 days.
        #
        # $1: host name (or ssh alias) *and* nixosSystem name
        ##
        push = pkgs.writeShellScriptBin "push" ''
          ${pkgs.lib.getBin self.packages.${system}.pull}/bin/pull --deploy-no-remote "$@"
        '';

        ##
        # "burn" the default image for use with terraform,
        # creating a garbage collector root './terraform/image'
        # which will not be clobbered when the next build overwrites './result'.
        ##
        burn = pkgs.writeShellApplication {
          name = "burn";
          runtimeInputs = with pkgs; [
            coreutils
            nix
          ];
          text = ''
            nix build --show-trace --out-link ./terraform/image --max-jobs auto --cores 0 .#images.default
          '';
        };

        ##
        # "cash" the last built derivation
        ##
        cash = pkgs.writeShellApplication {
          name = "cash";
          runtimeInputs = with pkgs; [
            jq
            nix
          ];
          text = ''
            nix flake archive --json \
              | jq -r '.path,(.inputs | to_entries[].value.path)' \
              | cachix push "$@"
            nix path-info --recursive ./result \
              | cachix push "$@"
          '';
        };
      };
    });
}
