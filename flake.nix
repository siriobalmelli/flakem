##
# dropflake: Lightweight deployment tooling for NixOS systems declared in Flakes
#
# 2023 Sirio Balmelli
##
{
  description = "dropflake";

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
        # Build '$1' on '$1' remote;
        # switch '$1' to built configuration;
        # collect garbage older than 15 days.
        #
        # $1: host name (or ssh alias) *and* nixosSystem name
        ##
        deploy = pkgs.writeShellApplication {
          name = "deploy";
          runtimeInputs = with pkgs; [
            nixos-rebuild
          ];
          text = builtins.readFile ./scripts/deploy.sh;
        };
        ##
        # Build '$1' locally;
        # switch '$1' to built configuration;
        # collect garbage older than 15 days.
        #
        # $1: host name (or ssh alias) *and* nixosSystem name
        ##
        dropship = pkgs.writeShellScriptBin "dropship" ''
          ${pkgs.lib.getBin self.packages.${system}.deploy}/bin/deploy --deploy-no-remote "$@"
        '';
      };
    });
}
