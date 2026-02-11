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

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      inherit (flake-utils.lib) eachDefaultSystem;
    in
    {
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.packages.flakem;
          inherit (lib) mkEnableOption mkIf;
        in
        {
          options.packages.flakem.enable = mkEnableOption "flakem tools";

          config = mkIf cfg.enable {
            nixpkgs.overlays = [ self.overlays.default ];
            environment.systemPackages = with pkgs; [
              build
              build-there
              hm-push
              hm-pull
              hm-switch
              ssh-deploy
              ssh-wait
              switch
              switch-pull
              switch-pull-reset
              switch-push
              switch-push-reset
            ];
          };
        };

      darwinModules.default = self.nixosModules.default;

      overlays.default = final: prev: {
        inherit (prev.callPackage ./package.nix { inherit (prev.lib) makeScope; })
          build
          build-there
          hm-push
          hm-pull
          hm-switch
          ssh-wait
          switch
          switch-pull
          switch-pull-reset
          switch-push
          switch-push-reset
          ;
        ssh-deploy = prev.callPackage ./ssh-deploy.nix { };
      };
    }
    // eachDefaultSystem (system: {
      packages =
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          inherit (pkgs)
            build
            build-there
            hm-push
            hm-pull
            hm-switch
            ssh-deploy
            ssh-wait
            switch
            switch-pull
            switch-pull-reset
            switch-push
            switch-push-reset
            ;
        };
    });
}
