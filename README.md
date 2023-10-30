# dropflake: Lightweight deployment tooling for NixOS systems declared in Flakes

This is a simple, opinionated nix deployment tool.

## Usage

### Run directly from git on a local flake directory:

    # build and deploy remotely
    nix run github:siriobalmelli/dropflake/master#deploy DESTINATION_HOST

    # build locally, deploy remotely
    nix run github:siriobalmelli/dropflake/master#dropship DESTINATION_HOST

### Include into a flake to deploy NixOS systems directly:

    TODO

### Options

    TODO

## TODO

- complete these docs
- CI with `nix flake update`
