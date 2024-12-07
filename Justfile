MKOSI_COMMIT := "5182007dcefd76c11bb2c5cd28013369c97121d4"
MKOSI_SOURCE := "git+https://github.com/systemd/mkosi.git@" + MKOSI_COMMIT
export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export BASETREE := justfile_directory() + "/mkosi.basetree"
INIT := "set ${DEBUG:+-x} -euo pipefail\n{ command -v mkosi >/dev/null || source .venv/bin/activate; }"

[private]
default:
    just --list


# List available recipes
list:
    #!/usr/bin/bash
    set ${DEBUG:+-x} -euo pipefail

    for recipe in recipes/*; do
        [[ -d $recipe ]] && echo "${recipe##*/}"
    done

# Install required tooling
setup $FORCE="":
    #!/usr/bin/bash
    {{ INIT }} || true

    if [[ $FORCE == "force" || -z $(command -v mkosi) ]]; then
        [[ $FORCE == "force" ]] && printf >&2 "Detected force flag: "
        echo >&2 "Installing mkosi..."
        python -m venv .venv
        source .venv/bin/activate
        pip install "{{ MKOSI_SOURCE }}"
        echo -e >&2 "\n\nExecute 'source .venv/bin/activate' to add mkosi to your PATH"
    else
        echo -e >&2 "mkosi already installed."
    fi


clean RECIPE="":
    #!/usr/bin/bash
    {{ INIT }}

    mkosi clean
    rm -rf mkosi.{output,cache}/*
    rm -rf $BASETREE

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
