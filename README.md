# flakem (Flake to Machine): Lightweight tooling for NixOS and Darwin systems declared in Flakes

Simple, opinionated wrappers around [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild),
[nix-darwin](https://github.com/LnL7/nix-darwin), and [home-manager](https://nix-community.github.io/home-manager/).

All wrappers are in the form `COMMAND MACHINE_NAME [NIX_OPTIONS]`, example:

```bash
# build 'bigmachine' remotely on 'myname@bigmachine', switch 'bigmachine' to the built config
switch-pull myname@bigmachine --show-trace
```

Flakem assumes that `MACHINE_NAME` is the same in both `flake.nix` and one of:

- IP address
- DNS name
- `host` string in SSH config

For NixOS, the target should be an installed NixOS system;
initial deployment can be done with
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere), eg:

```bash
nix run github:nix-community/nixos-anywhere -- \
    --flake .#HOSTNAME --build-on-remote root@HOST_IP
```

## Usage

![diagram of flakem workflow](docs/workflow.svg)

### System commands (NixOS and Darwin)

The `build` and `switch` commands auto-detect Darwin hosts via `uname -s`
and use `nix build .#darwinConfigurations...` + `./result/activate` instead of `nixos-rebuild`.

Remote commands (`build-there`, `switch-push`, `switch-pull`, etc.) are NixOS-only.

```bash
# build machine locally (auto-detects NixOS or Darwin)
nix run github:siriobalmelli/flakem/master#build $(hostname)

# build machine locally, apply locally (auto-detects NixOS or Darwin)
nix run github:siriobalmelli/flakem/master#switch $(hostname)

# build machine remotely (NixOS only)
nix run github:siriobalmelli/flakem/master#build-there bigmachine  # can also be 'myuser@bigmachine'

# build machine remotely, apply remotely (NixOS only)
nix run github:siriobalmelli/flakem/master#switch-pull myuser@bigmachine  # can also be 'bigmachine'

# build machine locally, apply remotely (NixOS only)
nix run github:siriobalmelli/flakem/master#switch-push bigmachine  # can also be 'myuser@bigmachine'

# switch-pull, followed by a reboot and a nix-collect-garbage
nix run github:siriobalmelli/flakem/master#switch-pull-reset root@10.3.2.1 another-machine

# switch-push, followed by a reboot and a nix-collect-garbage
nix run github:siriobalmelli/flakem/master#switch-push-reset 192.168.42.43 internal-machine

# timeout-loop waiting for successful ssh
nix run github:siriobalmelli/flakem/master#ssh-wait my-host "uname -a"

# decrypt and deploy a SOPS private key to a machine
nix run github:siriobalmelli/flakem/master#ssh-deploy my-host
```

### Home-Manager commands

Standalone Home-Manager deployment commands for `homeConfigurations` in your flake.

```bash
# switch home-manager config locally (auto-detects user@hostname)
nix run github:siriobalmelli/flakem/master#hm-switch

# switch home-manager config locally (explicit target)
nix run github:siriobalmelli/flakem/master#hm-switch sirio@panigale --show-trace

# build home-manager locally, copy closure to remote, activate remotely
nix run github:siriobalmelli/flakem/master#hm-push sirio@panigale

# hm-push with explicit flake target different from SSH host
nix run github:siriobalmelli/flakem/master#hm-push sirio@192.168.1.10 panigale

# ssh to remote, build and activate home-manager there (flake must exist on remote)
nix run github:siriobalmelli/flakem/master#hm-pull sirio@panigale
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

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    flakem,
  }: let
    inherit (flake-utils.lib) eachDefaultSystem;
  in
    eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [self.overlays.default];
      };
    in {
      packages = {
        inherit (pkgs) build build-there hm-push hm-pull hm-switch ssh-deploy ssh-wait switch switch-pull switch-pull-reset switch-push switch-push-reset;
        # ... other packages here
      };
    })
    // {
      nixosConfigurations = {
        bigmachine = nixpkgs.lib.nixosSystem {
          # NixOS configuration
        };
      };
    };
}
```

Then, from that flake's directory:

```bash
# build and deploy remotely
nix run .#switch-pull bigmachine

# etc ...
```

### Add flakem's tooling to system packages

On NixOS:

```nix
# called from a flake with 'specialArgs = { inherit inputs; };'
{inputs, lib, ...}: with lib; {
  imports = [
    inputs.flakem.nixosModules.default
  ];

  packages.flakem.enable = mkDefault true;
}
```

On Darwin (nix-darwin):

```nix
# called from a flake with 'specialArgs = { inherit inputs; };'
{inputs, lib, ...}: with lib; {
  imports = [
    inputs.flakem.darwinModules.default
  ];

  packages.flakem.enable = mkDefault true;
}
```

Both modules expose all flakem commands (system + Home-Manager).

## How it works

System commands (`build`, `switch`, etc.) detect the OS at runtime via `uname -s`:

- **Linux**: uses `nixos-rebuild` with `--fast --use-remote-sudo --use-substitutes`
- **Darwin**: uses `nix build .#darwinConfigurations.<host>.system` followed by `./result/activate`

Remote commands (`build-there`, `switch-push`, `switch-pull`, etc.) always use `nixos-rebuild`
and are NixOS-only.

Home-Manager commands (`hm-switch`, `hm-push`, `hm-pull`) use `home-manager` CLI
or direct activation of the built `activationPackage`.

All scripts execute with `set -x` to show the exact commands being run.

## TODO

- CI with `nix flake update`
- Remote Darwin deployment support
