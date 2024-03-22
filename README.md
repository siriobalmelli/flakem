# flakem (Flake to Machine): Lightweight tooling for NixOS systems declared in Flakes

This is a set of simple, opinionated wrappers around [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild)

All wrappers are in the form `COMMAND MACHINE_NAME [NIX_OPTIONS]`, example:

```bash
# build 'bigmachine' remotely on 'myname@bigmachine', switch 'bigmachine' to the built config
switch-pull myname@bigmachine --show-trace
```

Flakem assumes that `MACHINE_NAME` is the same in both `flake.nix` and one of:

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
# build machine locally
nix run github:siriobalmelli/flakem/master#build $(hostname)

# build machine remotely
nix run github:siriobalmelli/flakem/master#build-there bigmachine  # can also be 'myuser@bigmachine'

# build machine locally, apply locally
nix run github:siriobalmelli/flakem/master#switch $(hostname)

# build machine locally, apply remotely
nix run github:siriobalmelli/flakem/master#switch-push bigmachine  # can also be 'myuser@bigmachine'

# build machine remotely, apply remotely
nix run github:siriobalmelli/flakem/master#switch-pull myuser@bigmachine  # can also be 'bigmachine'
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
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flakem }: let
    inherit (flake-utils.lib) eachDefaultSystem;
  in
    eachDefaultSystem (system: {
      packages = {
        inherit (flakem.packages.${system}) build build-there switch switch-push switch-pull
      };
    });
}
```

Then, from that flake's directory:

```bash
# build and deploy remotely
nix run .#switch-pull bigmachine

# etc ...
```

## A note on `nixos-rebuild`

These scripts are really only shorthands for invocations of `nixos-rebuild`,
which also supply the `nixos-rebuild` dependency.

All scripts execute with `set -x` to show the exact parameter set being passed
to `nixos-rebuild`.

Note that `nixos-rebuild` will run on non-nixos hosts, such as Darwin.

## TODO

- CI with `nix flake update`
