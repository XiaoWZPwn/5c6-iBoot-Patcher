#!/usr/bin/env bash
# Fixture-only directory resolution checks. No USB or firmware writes.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/exploit.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/patcher-workspace.XXXXXX")
fixture=$(p5_abs "$fixture")
trap 'rm -rf -- "$fixture"' EXIT
ECID=3928855993768
MODEL=iPhone5,3
version="$fixture/project with spaces/runtime/firmware/6.1.4"
mkdir -p "$version/session"
for key in kernel devicetree ibss ibec; do printf '%s component\n' "$key" > "$version/session/$key"; done
jq -n --arg kernel "$(p5_sha "$version/session/kernel")" --arg tree "$(p5_sha "$version/session/devicetree")" --arg ibss "$(p5_sha "$version/session/ibss")" --arg ibec "$(p5_sha "$version/session/ibec")" '{target:"N48AP",source_version:{ProductVersion:"6.1.4",ProductBuildVersion:"10B350"},components:{kernel:"kernel",devicetree:"devicetree",ibss:"ibss",ibec:"ibec"},integrity_receipts:{kernel:$kernel,devicetree:$tree,ibss:$ibss,ibec:$ibec}}' > "$version/session/restore.json"
SYSTEM=$version
ex_resolve_system
[ ! -e "$version/session/result.json" ]
for selected in "$version" "$version/session" "$fixture/project with spaces" "$fixture/project with spaces/runtime" "$fixture/project with spaces/runtime/firmware"; do
    SYSTEM=$selected
    ex_resolve_system
    [ "$SYSTEM" = "$version" ] || { p5_fail 'Workspace normalized incorrectly'; exit 1; }
done
cp "$version/session/kernel" "$fixture/kernel-backup"
printf corrupted > "$version/session/kernel"
SYSTEM=$version
if ex_resolve_system > "$fixture/wrong.log" 2>&1; then p5_fail 'Changed component accepted'; exit 1; fi
cp "$fixture/kernel-backup" "$version/session/kernel"
WORK="$fixture/imported"
ex_import_system
[ ! -e "$SYSTEM/session/result.json" ]
ex_system_check
mkdir -p "$fixture/project with spaces/runtime/firmware/other/session"
cp "$version/session/"* "$fixture/project with spaces/runtime/firmware/other/session/"
SYSTEM="$fixture/project with spaces"
if ex_resolve_system > "$fixture/multiple.log" 2>&1; then p5_fail 'Ambiguous workspaces accepted'; exit 1; fi
p5_log 'Workspace checks passed: no result.json, component integrity, import, directory levels and ambiguity'
