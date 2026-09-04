#!/usr/bin/env bash
# Stage: interactive shell inside the builder container (./build.sh shell).
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export ARCH=arm64 CROSS_COMPILE
cd "$TOP"
log "builder shell; TOP=$TOP SRC=$SRC OUT=$OUT (ARCH/CROSS_COMPILE exported)"
exec bash "$@"
