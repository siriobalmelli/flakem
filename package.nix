{
  lib,
  makeScope,
  newScope,
  stdenv,
  writeShellApplication,

  nixos-rebuild,
  openssh,
  home-manager,
  nix,
}:
let
  rebuildOpts = lib.cli.toCommandLineShellGNU { } {
    fast = true;
    use-remote-sudo = true;
    use-substitutes = true;
  };

  nixosRebuildOpts = lib.cli.toCommandLineShellGNU { } {
    max-jobs = "auto";
    cores = 0;
  };

  shellApp =
    name:
    {
      commandLine,
      defaultHost ? "",
    }:
    {
      ${name} = writeShellApplication {
        inherit name;
        runtimeInputs = [
          nixos-rebuild
          nix
        ];
        text = ''
          die() {
            echo "$*" >&2
            exit 1
          }

          # detect OS for Darwin vs NixOS
          OS_TYPE="$(uname -s)"

          DEPLOY_HOST=
          FLAKE_TARGET=
          NIX_OPTIONS=( )
          while [ "$#" -gt 0 ]; do
            if [ -z "$DEPLOY_HOST" ]; then
              DEPLOY_HOST="$1"
              shift
            elif [ "''${1:0:1}" = "-" ]; then
              break;
            elif [ -z "$FLAKE_TARGET" ]; then
              FLAKE_TARGET="$1"
              shift
            else
              break
            fi
          done

          DEPLOY_HOST="''${DEPLOY_HOST:-${defaultHost}}" # conditional default
          [ -z "$DEPLOY_HOST" ] && die "no target given"

          [ -z "$FLAKE_TARGET" ] && FLAKE_TARGET="''${DEPLOY_HOST##*@}"  # remove a leading 'user@' stanza
          NIX_OPTIONS=("''${@:1}")  # any remaining options are nix options

          # avoid unused variable warnings
          export DEPLOY_HOST
          export FLAKE_TARGET
          export NIX_OPTIONS
          export OS_TYPE
          set -x

          ${commandLine}
        '';
      };
    };
in
makeScope newScope (
  self:
  ##
  # All scripts take:
  #
  # $1      : user@machine:
  #           user@machine  : stanza given to SSH for remote access
  #           machine       : name of NixOS system declared in flake
  # ${@:2}  : nix options
  #           options passed to nix as-is
  ##
  lib.concatMapAttrs shellApp {
    # build machine locally
    # ... remember `'$` escape oddity
    "build" = {
      defaultHost = "$(hostname -s)";
      commandLine = ''
        if [ "$OS_TYPE" = "Darwin" ]; then
          nix build --no-link --print-out-paths \
            ".#darwinConfigurations.$FLAKE_TARGET.system" \
            "''${NIX_OPTIONS[@]}"
        else
          nixos-rebuild build \
            ${rebuildOpts} --flake ".#$FLAKE_TARGET" \
            ${nixosRebuildOpts} "''${NIX_OPTIONS[@]}"
        fi
      '';
    };

    # build machine remotely
    "build-there" = {
      commandLine = ''
        nixos-rebuild build \
          ${rebuildOpts} --build-host "$DEPLOY_HOST" --target-host "$DEPLOY_HOST" \
          --flake ".#$FLAKE_TARGET" \
          ${nixosRebuildOpts} "''${NIX_OPTIONS[@]}"
      '';
    };

    # build machine locally, apply locally
    "switch" = {
      defaultHost = "$(hostname -s)";
      commandLine = ''
        if [ "$OS_TYPE" = "Darwin" ]; then
          OUT_PATH=$(nix build --no-link --print-out-paths \
            ".#darwinConfigurations.$FLAKE_TARGET.system" \
            "''${NIX_OPTIONS[@]}")
          sudo "$OUT_PATH/activate"
        else
          nixos-rebuild switch \
            ${rebuildOpts} --flake ".#$FLAKE_TARGET" \
            ${nixosRebuildOpts} "''${NIX_OPTIONS[@]}"
        fi
      '';
    };

    # build machine remotely, apply remotely
    "switch-pull" = {
      commandLine = ''
        nixos-rebuild switch \
          ${rebuildOpts} --build-host "$DEPLOY_HOST" --target-host "$DEPLOY_HOST" \
          --flake ".#$FLAKE_TARGET" \
          ${nixosRebuildOpts} "''${NIX_OPTIONS[@]}"
      '';
    };

    # build machine locally, apply remotely
    "switch-push" = {
      commandLine = ''
        nixos-rebuild switch \
          ${rebuildOpts} --target-host "$DEPLOY_HOST" --flake ".#$FLAKE_TARGET" \
          ${nixosRebuildOpts} "''${NIX_OPTIONS[@]}"
      '';
    };
  }
  // {
    # timeout-loop waiting for successful ssh
    ssh-wait = writeShellApplication {
      name = "ssh-wait";
      runtimeInputs = [ openssh ];
      text = ''
        while ! ssh -o ConnectTimeout=5 -o ServerAliveInterval=5 "$@"; do
          echo "$(date) ssh-wait: $*"
        done
      '';
    };

    # switch-pull, followed by a reboot and a nix-collect-garbage
    switch-pull-reset = writeShellApplication {
      name = "switch-pull-reset";
      runtimeInputs = with self; [
        ssh-wait
        switch-pull
      ];
      text = # bash
        ''
          switch-pull "$@"
          ssh "$1" "sudo reboot && while echo \"\$(date): waiting for reboot\"; do sleep 1; done" || true
          sleep 1  # patience: sometimes machines will *still* allow reconnect
          ssh-wait "$1" "sudo nix-collect-garbage --delete-older-than 15d"
        '';
    };

    # switch-push, followed by a reboot and a nix-collect-garbage
    switch-push-reset = writeShellApplication {
      name = "switch-push-reset";
      runtimeInputs = with self; [
        ssh-wait
        switch-push
      ];
      text = ''
        switch-push "$@"
        ssh "$1" "sudo reboot && while echo \"\$(date): waiting for reboot\"; do sleep 1; done" || true
        sleep 1  # patience: sometimes machines will *still* allow reconnect
        ssh-wait "$1" "sudo nix-collect-garbage --delete-older-than 15d"
      '';
    };

    # home-manager switch locally
    hm-switch = writeShellApplication {
      name = "hm-switch";
      runtimeInputs = [ home-manager ];
      text = ''
        die() {
          echo "$*" >&2
          exit 1
        }

        if [ "$#" -eq 0 ]; then
          TARGET="$(whoami)@$(hostname -s)"
        else
          TARGET="$1"
          shift
        fi

        set -x
        home-manager switch --flake ".#$TARGET" "$@"
      '';
    };

    # home-manager push: build locally, copy closure, activate remotely
    hm-push = writeShellApplication {
      name = "hm-push";
      runtimeInputs = [
        nix
        openssh
      ];
      text = ''
        die() {
          echo "$*" >&2
          exit 1
        }

        SSH_TARGET=
        FLAKE_TARGET=
        while [ "$#" -gt 0 ]; do
          if [ -z "$SSH_TARGET" ]; then
            SSH_TARGET="$1"
            shift
          elif [ "''${1:0:1}" = "-" ]; then
            break
          elif [ -z "$FLAKE_TARGET" ]; then
            FLAKE_TARGET="$1"
            shift
          else
            break
          fi
        done
        [ -z "$SSH_TARGET" ] && die "usage: hm-push USER@HOST [FLAKE_TARGET] [NIX_OPTIONS]"

        USER="''${SSH_TARGET%%@*}"
        HOST="''${SSH_TARGET##*@}"
        [ -z "$FLAKE_TARGET" ] && FLAKE_TARGET="$HOST"
        NIX_OPTIONS=("''${@:1}")

        set -x
        OUT_PATH=$(nix build --no-link --print-out-paths \
          ".#homeConfigurations.$USER@$FLAKE_TARGET.activationPackage" "''${NIX_OPTIONS[@]}")
        nix copy --to "ssh://$SSH_TARGET" "$OUT_PATH"
        # shellcheck disable=SC2029
        ssh "$SSH_TARGET" "$OUT_PATH/activate"
      '';
    };

    # home-manager pull: ssh to remote, build and activate there
    hm-pull = writeShellApplication {
      name = "hm-pull";
      runtimeInputs = [ openssh ];
      text = ''
        die() {
          echo "$*" >&2
          exit 1
        }

        SSH_TARGET=
        FLAKE_TARGET=
        while [ "$#" -gt 0 ]; do
          if [ -z "$SSH_TARGET" ]; then
            SSH_TARGET="$1"
            shift
          elif [ "''${1:0:1}" = "-" ]; then
            break
          elif [ -z "$FLAKE_TARGET" ]; then
            FLAKE_TARGET="$1"
            shift
          else
            break
          fi
        done
        [ -z "$SSH_TARGET" ] && die "usage: hm-pull USER@HOST [FLAKE_TARGET] [NIX_OPTIONS]"

        USER="''${SSH_TARGET%%@*}"
        HOST="''${SSH_TARGET##*@}"
        [ -z "$FLAKE_TARGET" ] && FLAKE_TARGET="$HOST"
        NIX_OPTIONS=("''${@:1}")

        # build remote command with safe quoting
        CMD="home-manager switch --flake '.#$USER@$FLAKE_TARGET'"
        for opt in "''${NIX_OPTIONS[@]}"; do
          CMD="$CMD $(printf '%q' "$opt")"
        done

        set -x
        # shellcheck disable=SC2029
        ssh "$SSH_TARGET" "$CMD"
      '';
    };
  }
)
