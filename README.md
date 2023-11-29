# flakem (Flake to Machine): Lightweight tooling for NixOS systems declared in Flakes

This is a simple, opinionated nix deployment tool.

It assumes that machine names are the same in both `flake.nix` and one of:

- IP address
- DNS name
- `host` string in SSH config

## Usage

### Run directly from git on a local flake directory:

    # build and deploy remotely
    nix run github:siriobalmelli/flakem/master#pull DESTINATION_HOST

    # build locally
    nix run github:siriobalmelli/flakem/master#here DESTINATION_HOST

    # build locally, deploy remotely
    nix run github:siriobalmelli/flakem/master#push DESTINATION_HOST

    # build .#images.default and link it to 'terraform/image'
    nix run github:siriobalmelli/flakem/master#burn

    # push the current './result' closure and all flake inputs to NIX_CACHE
    nix run github:siriobalmelli/flakem/master#cash NIX_CACHE

### Include into a flake to deploy NixOS systems directly:

```nix
{
  description = "My Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flakem = {
      url = "github:siriobalmelli/flakem";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flakem }: let
    inherit (flake-utils.lib) eachDefaultSystem;
  in
    eachDefaultSystem (system: {
      packages = {
        inherit (flakem.packages.${system}) pull here push burn cash;
      };
    });
}
```

Then, from that flake's directory:

    # build and deploy remotely
    nix run .#pull DESTINATION_HOST

    # etc ...

## TODO

- CI with `nix flake update`
