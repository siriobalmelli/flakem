# flakem

Lightweight tooling for NixOS and Darwin systems declared in Flakes.

## Architecture

Wraps `nixos-rebuild`, `nix-darwin`, and `home-manager` into unified commands like `build`, `switch`, `switch-pull`.
Auto-detects OS (Linux vs Darwin) to choose the correct backend (`nixos-rebuild` vs `nix build`).
Defined primarily in [`package.nix`](package.nix).

## Extension Protocols

### Adding New Commands

To add a new command (e.g., `hm-build`):

1.  **Define the command** in [`package.nix`](package.nix).
    - **Simple pattern** (local-only, e.g., [`hm-build`](package.nix#L190-L210)): uses basic argument parsing.
    - **Complex pattern** (remote ops, e.g., [`hm-push`](package.nix#L235-L276)): handles SSH targets and flake targets explicitly.

2.  **Register the command** in [`flake.nix`](flake.nix) in **THREE** places (must be kept in alphabetical order):
    - Module's `environment.systemPackages`: [`flake.nix` L40-54](flake.nix#L40-L54)
    - Overlay's `inherit`: [`flake.nix` L60-74](flake.nix#L60-L74)
    - Packages output's `inherit`: [`flake.nix` L87-101](flake.nix#L87-L101)

## Invariants

- **`nix build` vs `nixos-rebuild` flags**: `nix build` (used for Darwin) does NOT accept `--cores` or `--max-jobs`. These flags must be scoped strictly to `nixos-rebuild` invocations via [`nixosRebuildOpts`](package.nix#L20) and never applied globally to all nix commands.
