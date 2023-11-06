#!/usr/bin/env bash
set -e

# arguments
TARGET=
NO_REMOTE=
ARGS=( )
while [ "$#" -gt 0 ]; do
	case "$1" in
		--deploy-no-remote)
			NO_REMOTE=1
			;;
		# consider the first unnamed option as a target, the rest as arguments for nixos-rebuild
		*)
			if [ -z "$TARGET" ]; then
				TARGET="$1"
			else
				ARGS+=("$1")
			fi
			;;
	esac
	shift
done

# sanity checks
if [ -z "$TARGET" ]; then
	echo "no target specified" >&2
	exit 1
fi

# arguments
ARGS+=( \
	--max-jobs auto \
	--cores 0 \
	--target-host "$TARGET" \
	--use-remote-sudo \
	--use-substitutes \
)
if [ -z "$NO_REMOTE" ]; then
	ARGS+=( \
		--build-host "$TARGET" \
	)
fi

# run
nixos-rebuild switch --fast --flake .#"${TARGET##*@}" "${ARGS[@]}"
ssh -t "$TARGET" "sudo nix-collect-garbage --delete-older-than 15d"
