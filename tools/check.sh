#!/usr/bin/env bash
# Offline checks only: never connects to USB or runs a restore.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/exploit.sh"
ex_verify
system='{"first":6,"last":292686,"guid":"FDFB6C23-1F0D-4AB0-A01F-FFDC7C199D61","hfs":true,"flags":"0000000000000000"}'
data='{"first":292687,"last":3870725,"guid":"7A186453-BDFE-4B4E-A8E5-D704FE9D23E9","hfs":true,"flags":"0001000000000000"}'
table=$'Logical sector size: 4096 bytes\nFirst usable sector is 6, last usable sector is 3870725\n 1 6 292686 System\n 2 292687 3870725 Data'
geo=$(ex_geometry "$table" "$system" "$data")
printf '%s' "$geo"|jq -e '.resume==false and .partition3_first==3868550 and .partition4_first==3868678 and .new_data_bytes==14646734848' >/dev/null
data=$(printf '%s' "$data"|jq '.last=3868549')
p3='{"first":3868550,"last":3868677,"hfs":true}'
p4='{"first":3868678,"last":3870725,"hfs":true}'
table+=$'\n 3 3868550 3868677 exploit\n 4 3868678 3870725 Boot'
ex_geometry "$table" "$system" "$data" "$p3" "$p4"|jq -e '.resume==true' >/dev/null
bad=$(printf '%s' "$p4"|jq '.first=3868679')
if ex_geometry "$table" "$system" "$data" "$p3" "$bad" >/dev/null 2>&1; then p5_fail 'Overlapping/misaligned GPT accepted'; exit 2; fi
if ex_geometry "${table/4096/512}" "$system" "$data" "$p3" "$p4" >/dev/null 2>&1; then p5_fail 'Unexpected sector size accepted'; exit 2; fi
if [ "$#" -gt 0 ]; then
    out=$(p5_abs "$1")
    p5_plist "$out/Restore.plist" | jq -e '.Project5CNOROnly==true and .Project5CUntethered.BaseBuild=="11D257"' >/dev/null
    p5_temp
    for name in options.plist options.n48.plist; do
        p5_hfs_run 30 "$P5_TOOLS" "$out/RestoreRamDisk.hfs" extract "usr/local/share/restore/$name" "$P5_TMP/$name"
        p5_plist "$P5_TMP/$name"|jq -e '.FlashNOR==true and .UpdateBaseband==false and .SystemImage==false and .CreateFilesystemPartitions==false and .FormatForLwVM==false' >/dev/null
    done
    p5_zip_member "$out/NOR.ipsw" Restore.plist "$P5_TMP/Restore.plist"
    cmp "$out/Restore.plist" "$P5_TMP/Restore.plist"
    while IFS=$'\t' read -r rel sha; do [ "$(p5_sha "$out/$rel")" = "$sha" ]; done < <(jq -r 'to_entries[]|[.key,.value]|@tsv' "$out/checksums.json")
fi
p5_log 'Offline checks passed: geometry, rejection cases, resources and optional NOR package'
