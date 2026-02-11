# flakem

Lightweight tooling for NixOS and Darwin systems declared in Flakes.

## Architecture

Wraps `nixos-rebuild`, `nix-darwin`, and `home-manager` into unified commands like `build`, `switch`, `switch-pull`.
Auto-detects OS (Linux vs Darwin) to choose the correct backend (`nixos-rebuild` vs `nix build`).
Defined primarily in [`package.nix`](package.nix).

## Invariants

- **`nix build` vs `nixos-rebuild` flags**: `nix build` (used for Darwin) does NOT accept `--cores` or `--max-jobs`. These flags must be scoped strictly to `nixos-rebuild` invocations via [`nixosRebuildOpts`](package.nix#L20) and never applied globally to all nix commands.
