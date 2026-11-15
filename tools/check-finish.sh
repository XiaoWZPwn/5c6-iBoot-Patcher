#!/usr/bin/env bash
# Simulated stages only; never accesses a device.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [ "${1:-}" = --stage ]; then
    source "$ROOT/lib/exploit.sh"
    RUN=$2
    P5_ROOT=$RUN/resources
    WORK=$RUN/work
    # Capture the requested failure in a variable; functions have own arguments.
    failure=$3
    ex_install() { printf 'install\n' >> "$WORK/stages"; [ "$failure" != install ]; }
    ex_inspect() {
        printf 'inspect\n' >> "$WORK/stages"
        [ "$failure" != inspect ]
        cp "$P5_ROOT/patches/untethered/ramdiskH" "$RUN/exploit-before"
        cp "$WORK/base/iBEC" "$RUN/iBEC-before"
        [ "$failure" != mismatch ] || printf bad > "$RUN/iBEC-before"
    }
    ex_proxy_stop() { :; }
    ex_reboot() { printf 'reboot\n' >> "$WORK/stages"; }
    ex_finish
    exit
fi
fixture=$(mktemp -d "${TMPDIR:-/tmp}/patcher-finish.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
for failure in none install inspect mismatch; do
    trial="$fixture/$failure"
    mkdir -p "$trial/resources/patches/untethered" "$trial/work/base"
    printf exploit > "$trial/resources/patches/untethered/ramdiskH"
    printf ibec > "$trial/work/base/iBEC"
    status=0
    bash "$0" --stage "$trial" "$failure" > "$trial/output" 2>&1 || status=$?
    if [ "$failure" = none ]; then
        [ "$status" = 0 ]
        [ "$(cat "$trial/work/stages")" = $'install\ninspect\nreboot' ]
    else
        [ "$status" != 0 ]
        if grep -q reboot "$trial/work/stages"; then exit 1; fi
    fi
done
printf 'Combined operation checks passed: ordered stages; no reboot on install, inspection or readback failure\n'
