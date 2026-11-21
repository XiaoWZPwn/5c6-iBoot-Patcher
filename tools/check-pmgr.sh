#!/usr/bin/env bash
# Offline: patch the pinned normal iBoot and verify exactly five changed bytes.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/untethered-common.sh"
source "$ROOT/lib/pmgr.sh"
p5_temp
input="$ROOT/resources/profiles/iBoot.n48.11D257.raw"
p5_pmgr_iboot_patch "$input" "$P5_TMP/patched"
cmp -l "$input" "$P5_TMP/patched" > "$P5_TMP/diff" || [ "$?" = 1 ]
awk 'BEGIN {ok=1} {if ($1!=133465 && $1!=133477 && $1!=133478 && $1!=133479 && $1!=133480) ok=0; n++} END {exit !(ok && n==5)}' "$P5_TMP/diff"
if p5_pmgr_iboot_check "$input" >/dev/null 2>&1; then p5_fail 'Legacy PMGR writer accepted'; exit 1; fi
if p5_pmgr_iboot_patch "$P5_TMP/patched" "$P5_TMP/second" >/dev/null 2>&1; then p5_fail 'Unexpected writer layout accepted'; exit 1; fi
p5_log 'Normal iBoot PMGR checks passed: dense u32 store, no reserved-word overwrite, other bytes preserved'
