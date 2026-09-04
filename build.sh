#!/usr/bin/env bash
# Top-level build driver for the ASUS Tinker Edge R Ubuntu 22.04 image.
#
#   ./build.sh builder     build the Docker builder image
#   ./build.sh fetch       repo init + repo sync all source trees into src/
#   ./build.sh uboot       build U-Boot + pack idbloader/uboot/trust with rkbin
#   ./build.sh kernel      build the 6.1 kernel, DTBs and modules
#   ./build.sh rootfs      debootstrap the Ubuntu 22.04 rootfs (privileged container)
#   ./build.sh image       assemble the GPT disk image (privileged container)
#   ./build.sh verify      static checks on the newest image (GPT, extlinux, DTB, rootfs)
#   ./build.sh all         uboot + kernel + rootfs + image + verify
#   ./build.sh shell       interactive shell inside the builder container
#   ./build.sh clean       remove out/
#
# All stages run inside the container described by docker/Dockerfile; only
# `fetch` (git/repo) and `builder` (docker build) run on the host.
# Configuration lives in configs/board.env (override via environment).

set -euo pipefail
TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOP
# shellcheck source=scripts/lib.sh
. "$TOP/scripts/lib.sh"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

do_fetch() {
    command -v repo >/dev/null || die "the 'repo' tool is required (https://gerrit.googlesource.com/git-repo)"
    local url="${REPO_MANIFEST_URL:-}"
    if [ -z "$url" ]; then
        url="$(git -C "$TOP" remote get-url origin 2>/dev/null || true)"
    fi
    if [ -z "$url" ]; then
        url="$TOP"   # offline: use this checkout as the manifest repository
        warn "no 'origin' remote; using local checkout $TOP as manifest repo"
    fi
    local branch="${REPO_MANIFEST_BRANCH:-$(git -C "$TOP" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
    local -a groups=()
    [ -n "${REPO_GROUPS:-}" ] && groups=(-g "$REPO_GROUPS")
    log "repo init -u $url -b $branch ${groups[*]:-}"
    ( cd "$TOP" && repo init -u "$url" -b "$branch" -m default.xml --no-clone-bundle "${groups[@]}" "$@" )
    log "repo sync"
    ( cd "$TOP" && repo sync -c --no-clone-bundle --no-tags -j"${REPO_SYNC_JOBS:-4}" )
    log "sources synced into $SRC"
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
    builder) build_builder_image ;;
    fetch)   do_fetch "$@" ;;
    uboot|kernel|verify)
        ensure_builder_image
        run_in_container "$cmd" "$@" ;;
    rootfs|image)
        ensure_builder_image
        run_in_container --privileged "$cmd" "$@" ;;
    all)
        ensure_builder_image
        run_in_container uboot
        run_in_container kernel
        run_in_container --privileged rootfs
        run_in_container --privileged image
        run_in_container verify ;;
    shell)
        ensure_builder_image
        run_in_container ${PRIVILEGED:+--privileged} shell "$@" ;;
    clean)
        log "removing $OUT (root-owned files removed via container)"
        if [ -d "$OUT" ]; then
            docker run --rm -v "$TOP:$TOP" "$BUILDER_IMAGE" rm -rf "$OUT" || rm -rf "$OUT"
        fi ;;
    help|-h|--help) usage ;;
    *) usage; die "unknown command: $cmd" ;;
esac
