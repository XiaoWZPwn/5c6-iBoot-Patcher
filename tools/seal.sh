#!/usr/bin/env bash
# Generate distribution checksums after building/reviewing bundled resources.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/untethered-common.sh"
hashes='{}'
walk() {
    local path rel
    for path in "$1"/*; do
        [ -e "$path" ] || continue
        if [ -d "$path" ]; then walk "$path"; else
            rel=${path#"$ROOT/"}
            hashes=$(printf '%s' "$hashes"|jq --arg rel "$rel" --arg sha "$(p5_sha "$path")" '.[$rel]=$sha')
        fi
    done
}
walk "$ROOT/resources/restore"
walk "$ROOT/resources/profiles"
walk "$ROOT/resources/kit/bin"
walk "$ROOT/resources/kit/resources"
walk "$ROOT/resources/kit/saved"
hashes=$(printf '%s' "$hashes"|jq --arg sha "$(p5_sha "$ROOT/resources/sshrd-profile.json")" '.["resources/sshrd-profile.json"]=$sha')
walk "$ROOT/patches/untethered"
walk "$ROOT/lib"
for path in "$ROOT"/bin/macos/*; do
    [ -f "$path" ] || continue
    rel=${path#"$ROOT/"}
    hashes=$(printf '%s' "$hashes"|jq --arg rel "$rel" --arg sha "$(p5_sha "$path")" '.[$rel]=$sha')
done
walk "$ROOT/bin/macos/lib"
walk "$ROOT/resources/locks"
printf '%s\n' "$hashes" > "$ROOT/resources/checksums.json"
