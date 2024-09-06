{
  lib,
  makeScope,
  newScope,
  stdenv,
  writeShellApplication,

  nixos-rebuild,
  openssh,
}: let
  rebuildOpts = lib.cli.toGNUCommandLineShell {} {
    fast = true;
    use-remote-sudo = true;
    use-substitutes = true;
  };

  nixOpts = lib.cli.toGNUCommandLineShell {} {
    max-jobs = "auto";
    cores = 0;
  };

  shellApp = name: commandLine: {
    ${name} = writeShellApplication {
      inherit name;
      runtimeInputs = [nixos-rebuild];
      text = ''
        die() {
          echo "$*" >&2
          exit 1
        }

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
        [ -z "$DEPLOY_HOST" ] && die "no target given"
        [ -z "$FLAKE_TARGET" ] && FLAKE_TARGET="''${DEPLOY_HOST##*@}"  # remove a leading 'user@' stanza
        NIX_OPTIONS=("''${@:1}")  # any remaining options are nix options

        # avoid unused variable warnings
        export DEPLOY_HOST
        export FLAKE_TARGET
        export NIX_OPTIONS
        set -x

        ${commandLine}
      '';
    };
  };
in
  makeScope newScope (self:
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
      "build" = ''
        nixos-rebuild build \
          ${rebuildOpts} --flake ".#$FLAKE_TARGET" \
          ${nixOpts} "''${NIX_OPTIONS[@]}"
      '';

      # build machine remotely
      "build-there" = ''
        nixos-rebuild build \
          ${rebuildOpts} --build-host "$DEPLOY_HOST" --target-host "$DEPLOY_HOST" \
          --flake ".#$FLAKE_TARGET" \
          ${nixOpts} "''${NIX_OPTIONS[@]}"
      '';

      # build machine locally, apply locally
      "switch" = ''
        nixos-rebuild switch \
          ${rebuildOpts} --flake ".#$FLAKE_TARGET" \
          ${nixOpts} "''${NIX_OPTIONS[@]}"
      '';

      # build machine remotely, apply remotely
      "switch-pull" = ''
        nixos-rebuild switch \
          ${rebuildOpts} --build-host "$DEPLOY_HOST" --target-host "$DEPLOY_HOST" \
          --flake ".#$FLAKE_TARGET" \
          ${nixOpts} "''${NIX_OPTIONS[@]}"
      '';

      # build machine locally, apply remotely
      "switch-push" = ''
        nixos-rebuild switch \
          ${rebuildOpts} --target-host "$DEPLOY_HOST" --flake ".#$FLAKE_TARGET" \
          ${nixOpts} "''${NIX_OPTIONS[@]}"
      '';
    }
    // {
      # timeout-loop waiting for successful ssh
      ssh-wait = writeShellApplication {
        name = "ssh-wait";
        runtimeInputs = [openssh];
        text = ''
          while ! ssh -o ConnectTimeout=5 -o ServerAliveInterval=5 "$@"; do
            echo "$(date) ssh-wait: $*"
          done
        '';
      };

      # switch-pull, followed by a reboot and a nix-collect-garbage
      switch-pull-reset = writeShellApplication {
        name = "switch-pull-reset";
        runtimeInputs = with self; [ssh-wait switch-pull];
        text = ''
          switch-pull "$@"
          ssh "$1" "sudo reboot && while echo \"\$(date): waiting for reboot\"; do sleep 1; done" || true
          ssh-wait "$1" "sudo nix-collect-garbage --delete-older-than 15d"
        '';
      };

      # switch-push, followed by a reboot and a nix-collect-garbage
      switch-push-reset = writeShellApplication {
        name = "switch-push-reset";
        runtimeInputs = with self; [ssh-wait switch-push];
        text = ''
          switch-push "$@"
          ssh "$1" "sudo reboot && while echo \"\$(date): waiting for reboot\"; do sleep 1; done" || true
          ssh-wait "$1" "sudo nix-collect-garbage --delete-older-than 15d"
        '';
      };
    })
