# Common helpers for build.sh and the stage scripts.
# shellcheck shell=bash

set -euo pipefail

TOP="${TOP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="${SRC:-$TOP/src}"
OUT="${OUT:-$TOP/out}"
CONFIGS="$TOP/configs"
SCRIPTS="$TOP/scripts"

BUILDER_IMAGE="${BUILDER_IMAGE:-tinker-edge-r-builder:latest}"
CCACHE_DIR_HOST="${CCACHE_DIR_HOST:-$TOP/ccache}"

# shellcheck source=../configs/board.env
. "$CONFIGS/board.env"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

in_container() { [ -f /.dockerenv ] || [ "${TINKER_IN_CONTAINER:-0}" = 1 ]; }

require_src() {
    local d
    for d in "$@"; do
        [ -d "$SRC/$d" ] || die "missing $SRC/$d - run ./build.sh fetch first"
    done
}

# Run a stage script inside the builder container.
#   run_in_container [--privileged] <stage> [args...]
run_in_container() {
    local privileged=0
    if [ "${1:-}" = "--privileged" ]; then privileged=1; shift; fi
    local stage="$1"; shift
    local script="$SCRIPTS/stage-$stage.sh"
    [ -x "$script" ] || die "no such stage: $stage"
    mkdir -p "$OUT" "$CCACHE_DIR_HOST"

    local -a args=(run --rm -e TINKER_IN_CONTAINER=1 -e HOME=/tmp
                   -e TOP="$TOP" -e SRC="$SRC" -e OUT="$OUT"
                   -e CCACHE_DIR=/ccache -v "$CCACHE_DIR_HOST:/ccache"
                   -v "$TOP:$TOP" -w "$TOP")
    if [ -t 0 ] && [ -t 1 ]; then args+=(-it); fi
    if [ "$privileged" = 1 ]; then
        # debootstrap/chroot need CAP_SYS_ADMIN and the ability to mount; run as root.
        args+=(--privileged)
    else
        args+=(--user "$(id -u):$(id -g)")
    fi
    # Pass through every knob from configs/board.env that the caller overrode.
    local v
    for v in $(grep -oE '^[A-Z_]+=' "$CONFIGS/board.env" | tr -d '=' | sort -u); do
        if [ -n "${!v+x}" ]; then args+=(-e "$v=${!v}"); fi
    done
    log "container: stage $stage$( [ "$privileged" = 1 ] && echo ' (privileged, root)' )"
    docker "${args[@]}" "$BUILDER_IMAGE" "$script" "$@"
}

ensure_builder_image() {
    if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
        build_builder_image
    fi
}

build_builder_image() {
    log "building builder image $BUILDER_IMAGE"
    docker build -t "$BUILDER_IMAGE" "$TOP/docker"
}

# Stage-side helpers -------------------------------------------------------------

stage_banner() { log "==== $* ===="; }

# Verify that every "CONFIG_X=y|m" line in the given fragment files is present in .config.
check_config_fragments() {
    local config="$1"; shift
    local frag opt want missing=0
    for frag in "$@"; do
        while read -r line; do
            case "$line" in
                CONFIG_*=*)
                    opt="${line%%=*}"; want="${line#*=}"
                    if [ "$want" = "y" ] || [ "$want" = "m" ]; then
                        if ! grep -qx "$opt=$want" "$config"; then
                            # =m requested but built-in is acceptable
                            if [ "$want" = "m" ] && grep -qx "$opt=y" "$config"; then continue; fi
                            warn "$(basename "$frag"): $opt=$want not honoured (dependency missing?)"
                            missing=1
                        fi
                    fi
                    ;;
            esac
        done < "$frag"
    done
    return $missing
}
