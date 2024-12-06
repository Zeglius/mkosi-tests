MKOSI_COMMIT := "5182007dcefd76c11bb2c5cd28013369c97121d4"
MKOSI_SOURCE := "git+https://github.com/systemd/mkosi.git@" + MKOSI_COMMIT
export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export BASETREE := justfile_directory() + "/mkosi.basetree"

[private]
default:
    just --list

setup:
    #!/usr/bin/bash

    function commandq () {
        command -v $1 >/dev/null
        return
    }

    if ! commandq mkosi; then
        if ! commandq uv; then
            commandq brew || { exit 1; }
            brew install uv
        fi
        uv tool install {{ MKOSI_SOURCE }}
    fi

clean:
    #!/usr/bin/bash

    mkosi clean
    ${SUDOIF} rm -rf mkosi.{output,cache}/*
    if [[ -d $BASETREE ]]; then
        if [[ $(stat -f --format="%T" $BASETREE) == "btrfs" ]]; then
            sudo btrfs subvolume delete $BASETREE
        else
            sudo rm -rf $BASETREE
        fi
    fi

prepare-overlay-tar $IMAGE_REF:
    #!/usr/bin/bash

    set -e ${DEBUG:+-x}
    : ${IMAGE_REF?ERROR: missing container image reference}

    function mkdir_btrfs() {
        if [[ $(stat -f --format="%T" $(dirname "$1")) == "btrfs" ]]; then
            mkdir -p "$(dirname "$1")" && btrfs subvolume create "$1"
        else
            mkdir -p "$1"
        fi
    }

    just clean >&2
    echo >&2 "Preparing '$(basename "$BASETREE")'..."

    container=$(podman create --entrypoint /usr/bin/true $IMAGE_REF)
    trap "podman rm $container $([[ -n $CI ]] && echo " && podman rmi $IMAGE_REF")" EXIT
    mkdir_btrfs "$BASETREE"
    podman cp ${container}:/ "$BASETREE"
