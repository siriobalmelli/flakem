##
# Deploy AGE secret key securely over SSH:
#
#   ssh-deploy SSH_LOGIN [HOSTNAME]
##
{
  writeShellApplication,
  openssh,
  sops,
}:
writeShellApplication {
  name = "ssh-deploy";
  runtimeInputs = [
    openssh
    sops
  ];
  text = ''
    die() {
      echo "$*" >&2
      exit 1
    }

    HOSTNAME=
    SSH_LOGIN=
    if [ "$#" -eq 2 ]; then
      SSH_LOGIN="$1"
      HOSTNAME="$2"
    elif [ "$#" -eq 1 ]; then
      SSH_LOGIN="$1"
      HOSTNAME="''${SSH_LOGIN##*@}"
    else
      die "usage: $(basename "$0") SSH_LOGIN [HOSTNAME]"
    fi

    TGT="/var/lib/sops-nix"

    KEYFILE="hosts/''${HOSTNAME}/''${HOSTNAME}.age.key";
    [ -s "$KEYFILE" ] || die "missing keyfile '$KEYFILE'"

    set -x
    # client expansion desired
    # shellcheck disable=SC2029
    sops --decrypt "$KEYFILE" \
      | ssh "$SSH_LOGIN" "\
        sudo mkdir -p $TGT && cat | sudo tee $TGT/key.txt >/dev/null \
        && sudo chmod go-rwx $TGT/key.txt \
      "
  '';
}
