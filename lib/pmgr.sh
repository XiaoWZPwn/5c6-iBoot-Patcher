#!/usr/bin/env bash
# Normal N48 iBoot-1940.10.58 uses u64 firmware-m-perf-states cells;
# the iOS 6 DeviceTree/PMGR consumer uses dense u32 period cells instead.
p5_pmgr_iboot_check() {
    [ "$(p5_native hex-range "$1" 0x20956 4)" = 41f82500 ] &&
    [ "$(p5_native hex-range "$1" 0x20964 4)" = 00bf00bf ] || {
        p5_fail 'Prepared iBoot lacks the iOS 6 PMGR u32 handoff fix; rebuild base/NOR and reinstall the Boot partition iBEC'; return 2;
    }
}
p5_pmgr_iboot_patch() {
    local input=$1 output=$2
    # Version-specific full instruction sequence, including the divide, loop
    # bounds and original zero store. Never apply 7.0.1 iBEC offsets here.
    [ "$(p5_native hex-range "$input" 0x20946 36)" = 4ff04a4043f69a31002313f0fef9009941f83500009800ebc5000135a542c0f80480e9d3 ] || {
        p5_fail 'Unsupported normal iBoot PMGR writer layout'; return 2;
    }
    [ "$input" = "$output" ] || cp "$input" "$output" || return $?
    printf '%s' 41f82500 | xxd -r -p | dd of="$output" bs=1 seek=$((0x20956)) conv=notrunc 2>/dev/null || return $?
    printf '%s' 00bf00bf | xxd -r -p | dd of="$output" bs=1 seek=$((0x20964)) conv=notrunc 2>/dev/null || return $?
    p5_pmgr_iboot_check "$output"
}
