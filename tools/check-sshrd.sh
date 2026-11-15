#!/usr/bin/env bash
# Verify optional dependency handling without USB or network access.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/untethered-common.sh"
source "$ROOT/lib/sshrd.sh"
[ "$#" = 1 ] || { printf 'Usage: bash tools/check-sshrd.sh VERIFIED_COMPONENT_FOLDER\n' >&2; exit 2; }
source_dir=$(p5_abs "$1")
p5_sshrd_verify "$source_dir"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/p5-sshrd-check.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
if (unset P5_SSHRD_DIR P5_SSHRD_URL; p5_sshrd_ensure "$test_root/missing" < /dev/null) >/dev/null 2>&1; then exit 2; fi
P5_SSHRD_DIR=$source_dir p5_sshrd_ensure "$test_root/import"
cache="$test_root/import/saved/iPhone5,3/ramdisk_11D257/saved"
p5_sshrd_verify "$cache"
printf 'bad' > "$cache/iBSS"
if p5_sshrd_verify "$cache"; then exit 2; fi
bsdtar -czf "$test_root/ramdisk.tar.gz" -C "$source_dir" iBSS iBEC Ramdisk.dmg DeviceTree.dec Kernelcache.dec
# Stub the transport only: exercise real extraction, checksums and cache install.
curl() {
    local output=
    while [ "$#" -gt 0 ]; do
        if [ "$1" = --output ]; then output=$2; shift 2; else shift; fi
    done
    cp "$test_root/ramdisk.tar.gz" "$output"
}
unset P5_SSHRD_DIR
P5_SSHRD_URL=https://example.invalid/ramdisk.tar.gz p5_sshrd_ensure "$test_root/download"
p5_sshrd_verify "$test_root/download/saved/iPhone5,3/ramdisk_11D257/saved"
if P5_SSHRD_URL=http://example.invalid/ramdisk.tar.gz p5_sshrd_ensure "$test_root/insecure" >/dev/null 2>&1; then exit 2; fi
p5_log 'SSH RAM checks passed: missing cache, manual import, corrupt component, archive extraction, HTTPS requirement'
