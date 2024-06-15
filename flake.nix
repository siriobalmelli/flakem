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
    {
      overlays.default = final: prev: {
        inherit
          (prev.callPackage ./package.nix {inherit (prev.lib) makeScope;})
          build
          build-there
          switch
          switch-pull
          switch-pull-reset
          switch-push
          switch-push-reset
          ssh-wait
          ;
      };
    }
    // eachDefaultSystem (system: {
      packages = let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        };
      in {
        inherit (pkgs) build build-there switch switch-pull switch-pull-reset switch-push switch-push-reset ssh-wait;
      };
    });
}
