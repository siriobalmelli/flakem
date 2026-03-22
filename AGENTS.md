# flakem

Lightweight tooling for NixOS and Darwin systems declared in Flakes.

## Architecture

Wraps `nixos-rebuild`, `nix-darwin`, and `home-manager` into unified commands like `build`, `switch`, `switch-pull`.
Defined primarily in [`package.nix`](package.nix).

### OS Detection Strategy

- **Local commands** (`build`, `switch`): Use `uname -s` to detect the running OS.
- **Remote commands** (`switch-push`, `switch-pull`): Use `nix eval` to check if the target exists in `darwinConfigurations` or `nixosConfigurations` (since the remote OS may differ from local).

### Remote Operations

- **NixOS targets**: Delegate to `nixos-rebuild` with `--target-host`.
- **Darwin targets**:
  - **Push**: Build locally → `nix copy` closure to remote → SSH trigger activation (matches `hm-push` pattern).
  - **Pull**: SSH to remote → build and activate there. **Requires flake source on remote.**

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
- **Remote Ops Dependencies**: `openssh` must be in `shellApp` `runtimeInputs` to support `nix copy --to ssh://` and remote activation commands.
- **Darwin Pull Constraint**: Unlike NixOS, `switch-pull` for Darwin cannot copy the flake source; it assumes the source is already present and synced on the remote machine.
- **Darwin switch must update the profile before activating.** All Darwin `switch` code paths must call `sudo nix-env -p /nix/var/nix/profiles/system --set "$OUT_PATH"` before `sudo "$OUT_PATH/activate"`. Without this, the system profile is not updated and the next reboot reverts to the previous generation. This matches the order used by `darwin-rebuild switch` (profile first, then activate).
