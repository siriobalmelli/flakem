# dropflake: Lightweight deployment tooling for NixOS systems declared in Flakes

This is a simple, opinionated nix deployment tool.

## Usage

### Run directly from git on a local flake directory:

    # build and deploy remotely
    nix run github:siriobalmelli/dropflake/master#deploy DESTINATION_HOST

    # build locally, deploy remotely
    nix run github:siriobalmelli/dropflake/master#dropship DESTINATION_HOST

### Include into a flake to deploy NixOS systems directly:

```nix
{
  description = "My Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dropflake = {
      url = "github:siriobalmelli/dropflake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, dropflake }: let
    inherit (flake-utils.lib) eachDefaultSystem;
  in
    eachDefaultSystem (system: {
      packages = {
        inherit (dropflake.packages.${system}) deploy dropship;
      };
    });
}
```

Then, from that flake's directory:

    # build and deploy remotely
    nix run .#deploy DESTINATION_HOST

    # build locally, deploy remotely
    nix run .#dropship DESTINATION_HOST

## TODO

- CI with `nix flake update`
