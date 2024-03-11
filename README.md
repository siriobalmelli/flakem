# flakem (Flake to Machine): Lightweight tooling for NixOS systems declared in Flakes

This is a simple, opinionated nix deployment tool.

It assumes that machine names are the same in both `flake.nix` and one of:

- IP address
- DNS name
- `host` string in SSH config

It also assumes the target is already an installed NixOS system;
if this is not the case, initial deployment can be done with
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere), eg:

```bash
nix run github:nix-community/nixos-anywhere -- \
    --flake .#HOSTNAME --build-on-remote root@HOST_IP
```

## Usage

![diagram of flakem workflow](docs/workflow.svg)

### Run directly from git on a local flake directory:

```bash
# build and deploy remotely
nix run github:siriobalmelli/flakem/master#pull DESTINATION_HOST

# build locally
nix run github:siriobalmelli/flakem/master#here DESTINATION_HOST

# build locally, deploy remotely
nix run github:siriobalmelli/flakem/master#push DESTINATION_HOST

# build .#images.default and link it to 'terraform/image'
nix run github:siriobalmelli/flakem/master#burn
```

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
        inherit (flakem.packages.${system}) pull here push burn;
      };
    });
}
```

Then, from that flake's directory:

```bash
# build and deploy remotely
nix run .#pull DESTINATION_HOST

# etc ...
```

## TODO

- CI with `nix flake update`
