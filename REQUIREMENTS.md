# Flakem Extension Requirements

## Overview

Extend flakem to support **Darwin** (nix-darwin) systems and **Home-Manager** standalone configurations, in addition to the existing NixOS support. This will unify deployment tooling across all three configuration types under a single, consistent CLI.

## Background

**Current state:** flakem provides lightweight wrappers around `nixos-rebuild` for deploying NixOS systems declared in flakes. It offers commands like `build`, `switch`, `switch-push`, `switch-pull` that handle local and remote builds/deployments.

**Goal:** Extend flakem to:
1. Support Darwin systems (using `darwin-rebuild` instead of `nixos-rebuild`)
2. Add Home-Manager deployment commands (using `home-manager` CLI or direct activation)
3. Maintain the same simple, opinionated CLI patterns
4. Provide both NixOS and Darwin module integration

## Functional Requirements

### 1. Darwin Support for Existing Commands

All existing commands (`build`, `build-there`, `switch`, `switch-push`, `switch-pull`, `switch-pull-reset`, `switch-push-reset`) should support Darwin systems.

#### 1.1 Auto-Detection

Commands should auto-detect whether the target is a `darwinConfigurations.*` or `nixosConfigurations.*` entry in the flake and use the appropriate rebuild command:
- **NixOS**: `nixos-rebuild` (current behavior)
- **Darwin**: `darwin-rebuild`

**Detection method:** Query the flake metadata or accept an optional `--darwin` flag.

#### 1.2 Darwin-Specific Pre-Activation Step

For Darwin `switch` operations (local or remote), **before** running `darwin-rebuild switch`, the following files must be removed (only after a successful build):

```bash
sudo rm -fv /etc/{bashrc,zshrc,zshenv} /etc/nix/nix.conf
```

**Rationale:** These files conflict with nix-darwin's managed configurations and must be removed before activation.

**Implementation note:** This should be a configurable pre-activation hook, not hardcoded, to allow future extensibility.

#### 1.3 Command Behavior

| Command | Darwin Behavior |
|---------|----------------|
| `build` | Build Darwin system locally using `darwin-rebuild build` |
| `build-there` | Build Darwin system remotely (SSH to target, run `darwin-rebuild build`) |
| `switch` | Build locally, remove conflicting files, activate with `darwin-rebuild switch` |
| `switch-push` | Build locally, copy closure to remote, remove conflicting files remotely, activate remotely |
| `switch-pull` | SSH to remote, build there, remove conflicting files, activate with `darwin-rebuild switch` |
| `switch-pull-reset` | `switch-pull` + reboot + garbage collect (same as NixOS) |
| `switch-push-reset` | `switch-push` + reboot + garbage collect (same as NixOS) |

### 2. Home-Manager Commands (New)

Add three new commands for deploying standalone Home-Manager configurations.

#### 2.1 `hm-switch` (Local Home-Manager Switch)

**Signature:** `hm-switch [USER@HOST] [NIX_OPTIONS]`

**Behavior:**
- If `USER@HOST` is provided, use it as the flake target
- If not provided, auto-detect: `$(whoami)@$(hostname -s)`
- Run: `home-manager switch --flake ".#USER@HOST" [NIX_OPTIONS]`

**Example:**
```bash
# Auto-detect current user and host
hm-switch

# Explicit target
hm-switch sirio@panigale --show-trace
```

#### 2.2 `hm-push` (Remote Home-Manager Push)

**Signature:** `hm-push USER@HOST [FLAKE_TARGET] [NIX_OPTIONS]`

**Behavior:**
1. Parse `USER@HOST` (SSH target) and optional `FLAKE_TARGET` (defaults to hostname from SSH target)
2. Build the Home-Manager activation package locally:
   ```bash
   nix build ".#homeConfigurations.USER@FLAKE_TARGET.activationPackage"
   ```
3. Copy the closure to the remote:
   ```bash
   nix copy --to ssh://USER@HOST ./result
   ```
4. Activate remotely via SSH:
   ```bash
   ssh USER@HOST ./result/activate
   ```

**Example:**
```bash
# Push sirio@panigale config to remote host panigale
hm-push sirio@panigale

# Push with explicit flake target different from SSH host
hm-push sirio@192.168.1.10 panigale
```

#### 2.3 `hm-pull` (Remote Home-Manager Pull)

**Signature:** `hm-pull USER@HOST [FLAKE_TARGET] [NIX_OPTIONS]`

**Behavior:**
1. Parse `USER@HOST` and optional `FLAKE_TARGET`
2. SSH to remote and run:
   ```bash
   ssh USER@HOST "home-manager switch --flake '.#USER@FLAKE_TARGET' [NIX_OPTIONS]"
   ```

**Requirement:** The flake repository must exist on the remote machine.

**Example:**
```bash
# Pull-based deployment (build and activate on remote)
hm-pull sirio@panigale
```

### 3. Module Support

#### 3.1 `darwinModules.default` (New)

Add a Darwin module equivalent to the existing `nixosModules.default`.

**Structure:**
```nix
darwinModules.default = { config, lib, pkgs, ... }:
  let
    cfg = config.packages.flakem;
    inherit (lib) mkEnableOption mkIf;
  in {
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
```

**Note:** The module should expose **all** commands (system + HM), not just Darwin-specific ones.

#### 3.2 Update `nixosModules.default`

Add the new HM commands to the NixOS module's `environment.systemPackages`:
- `hm-switch`
- `hm-push`
- `hm-pull`

### 4. Package Exposure

All new commands must be exposed in:
1. **`overlays.default`** — so they're available via nixpkgs overlay
2. **`packages.<system>.*`** — so they're available as `nix run .#<command>`

**New packages:**
- `hm-switch`
- `hm-push`
- `hm-pull`

**Existing packages** (unchanged):
- `build`, `build-there`, `switch`, `switch-push`, `switch-pull`
- `switch-pull-reset`, `switch-push-reset`
- `ssh-wait`, `ssh-deploy`

## Architectural Hints

### Current Architecture

Flakem uses:
- **`writeShellApplication`** for creating shell script packages
- **`makeScope` / `newScope`** for organizing packages in `package.nix`
- **`lib.cli.toGNUCommandLineShell`** for formatting CLI options
- **Common argument parsing** via the `shellApp` helper function

All commands follow the pattern:
```
COMMAND TARGET [FLAKE_TARGET] [NIX_OPTIONS]
```

### Suggested Approach

#### Darwin Detection

Option A: **Flake metadata query**
```bash
# Check if target exists in darwinConfigurations
nix eval --raw ".#darwinConfigurations.$FLAKE_TARGET.config.system.name" 2>/dev/null && IS_DARWIN=true
```

Option B: **Explicit flag**
```bash
# Accept --darwin flag
if [[ "$1" == "--darwin" ]]; then
  IS_DARWIN=true
  shift
fi
```

**Recommendation:** Option A (auto-detect) with Option B (flag) as override. This maintains the "zero-config" philosophy while allowing explicit control.

#### Pre-Activation Hooks

Introduce a `preActivation` function that can be customized per OS:

```bash
preActivation() {
  if [ "$IS_DARWIN" = true ]; then
    sudo rm -fv /etc/{bashrc,zshrc,zshenv} /etc/nix/nix.conf
  fi
}
```

This allows future extension (e.g., NixOS-specific pre-activation steps).

#### Home-Manager Commands

These don't use `nixos-rebuild` or `darwin-rebuild` at all. They should be separate `writeShellApplication` definitions, not part of the `shellApp` helper (unless the helper is generalized).

**For `hm-switch`:**
```nix
hm-switch = writeShellApplication {
  name = "hm-switch";
  runtimeInputs = [ home-manager ];
  text = ''
    TARGET="''${1:-$(whoami)@$(hostname -s)}"
    shift || true
    home-manager switch --flake ".#$TARGET" "$@"
  '';
};
```

**For `hm-push`:**
```nix
hm-push = writeShellApplication {
  name = "hm-push";
  runtimeInputs = [ nix openssh ];
  text = ''
    # Parse USER@HOST and FLAKE_TARGET
    # Build activation package
    # nix copy to remote
    # ssh to activate
  '';
};
```

**For `hm-pull`:**
```nix
hm-pull = writeShellApplication {
  name = "hm-pull";
  runtimeInputs = [ openssh ];
  text = ''
    # Parse USER@HOST and FLAKE_TARGET
    # ssh to remote and run home-manager switch
  '';
};
```

### Runtime Dependencies

**New dependencies needed:**
- `home-manager` — for `hm-switch` and `hm-pull`
- `nix` — already available, but explicitly needed for `hm-push` (`nix build`, `nix copy`)

**Existing dependencies:**
- `nixos-rebuild` — NixOS commands
- `darwin-rebuild` — Darwin commands (needs to be added to `runtimeInputs` conditionally or always available on Darwin systems)
- `openssh` — remote operations

**Note:** `darwin-rebuild` is provided by the `nix-darwin` flake input on Darwin systems. It may not be available on NixOS hosts. Commands should gracefully handle this (e.g., fail with a clear error if trying to build a Darwin system from a NixOS host without `darwin-rebuild` available).

## Testing & Validation

### Test Cases

1. **Darwin local switch:**
   ```bash
   nix run .#switch panigale  # on a Darwin host
   ```
   Should detect Darwin, remove conflicting files, activate with `darwin-rebuild`.

2. **Darwin remote push:**
   ```bash
   nix run .#switch-push sirio@panigale  # from any host
   ```
   Should build locally, copy to remote Darwin host, remove files, activate.

3. **Home-Manager local switch:**
   ```bash
   nix run .#hm-switch  # auto-detect user@host
   nix run .#hm-switch sirio@panigale  # explicit target
   ```

4. **Home-Manager remote push:**
   ```bash
   nix run .#hm-push sirio@panigale
   ```
   Should build HM activation package locally, copy to remote, activate.

5. **Home-Manager remote pull:**
   ```bash
   nix run .#hm-pull sirio@panigale
   ```
   Should SSH to remote and run `home-manager switch` there.

### Validation

- All commands should execute with `set -x` to show exact invocations (current behavior)
- Error messages should be clear (e.g., "darwin-rebuild not found" if trying to build Darwin from NixOS)
- The `--help` or error output should show usage patterns

## Documentation Updates

### README.md

Add sections for:
1. **Darwin support** — examples of deploying Darwin systems
2. **Home-Manager support** — examples of `hm-switch`, `hm-push`, `hm-pull`
3. **Module usage on Darwin** — how to use `darwinModules.default`

### Workflow Diagram

Update `docs/workflow.svg` to include Darwin and Home-Manager deployment paths.

## Compatibility & Migration

### Backward Compatibility

All existing commands retain their current behavior for NixOS systems. No breaking changes.

### Migration Path for sbtools

Once flakem is updated, the sbtools repository will:
1. Update `flake.lock` to pull in the new flakem version
2. Remove local packages: `pkgs/darwin-build/`, `pkgs/darwin-switch/`, `pkgs/hm-switch/`
3. Update `features/flakem.nix` to conditionally import `nixosModules.default` or `darwinModules.default` based on `isDarwin`
4. Update documentation to reference flakem commands instead of local wrappers

## Success Criteria

- [ ] All existing NixOS commands work unchanged
- [ ] `build` and `switch` commands work on Darwin systems (local and remote)
- [ ] `hm-switch` works for local Home-Manager deployment
- [ ] `hm-push` works for remote Home-Manager deployment (build local, activate remote)
- [ ] `hm-pull` works for remote Home-Manager deployment (build remote, activate remote)
- [ ] `darwinModules.default` provides the same interface as `nixosModules.default`
- [ ] All commands exposed in overlay and packages outputs
- [ ] Documentation updated with examples
- [ ] `nix flake check` passes
- [ ] Manual testing on Darwin and NixOS hosts confirms functionality

## Open Questions

1. **Should `darwin-rebuild` be a runtime dependency on all systems, or only on Darwin?**
   - If only on Darwin, cross-platform builds (NixOS → Darwin) won't work
   - If on all systems, it adds a dependency that may not be available on NixOS

2. **Should Home-Manager commands accept a `--flake` flag to specify a different flake path?**
   - Current assumption: flake is in current directory (`.`)
   - Alternative: accept `--flake /path/to/flake` for flexibility

3. **Should the pre-activation hook be user-configurable?**
   - Current requirement: hardcoded file removal for Darwin
   - Future: allow users to specify custom pre-activation scripts?

## References

- [nixos-rebuild](https://nixos.wiki/wiki/Nixos-rebuild)
- [darwin-rebuild](https://daiderd.com/nix-darwin/manual/index.html#sec-usage)
- [home-manager](https://nix-community.github.io/home-manager/)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- Current flakem implementation: `package.nix`, `flake.nix`, `ssh-deploy.nix`
