#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/untethered-common.sh"
p5_recovery_fields() { p5_run_timeout 5 "$1" irecovery -q | awk 'match($0,/^[A-Z]+:/){key=substr($0,1,RLENGTH-1);value=substr($0,RLENGTH+1);sub(/^[ \t]+/,"",value);if(key=="ECID")sub(/[ \t]*\(.*/,"",value);print key "\t" value}' | jq -Rn '[inputs|split("\t")|{key:.[0],value:.[1]}]|from_entries'; }
p5_check_dfu() {
    local actual chip board mode
    actual=$(printf '%s' "$1"|jq -r '.ECID//"0"'); chip=$(printf '%s' "$1"|jq -r '.CPID//"0"'); board=$(printf '%s' "$1"|jq -r '.BDID//"0"'); mode=$(printf '%s' "$1"|jq -r '.MODE//""')
    [ "$((actual))" = "$(($2))" ] && [ "$((chip))" = 35152 ] && [ "$((board))" = "$(p5_target "$3"|jq -r .board_id)" ] && [ "$mode" = DFU ]
}
p5_check_recovery() {
    local actual chip board mode
    actual=$(printf '%s' "$1"|jq -r '.ECID//"0"'); chip=$(printf '%s' "$1"|jq -r '.CPID//"0"'); board=$(printf '%s' "$1"|jq -r '.BDID//"0"'); mode=$(printf '%s' "$1"|jq -r '.MODE//""')
    [ "$((actual))" = "$(($2))" ] && [ "$((chip))" = 35152 ] && [ "$((board))" = "$(p5_target "$3"|jq -r .board_id)" ] && [[ "$mode" = Recovery* ]]
}
p5_wait_recovery() {
    local n fields
    for n in 1 2 3 4 5 6 7 8 9 10; do
        fields=$(p5_recovery_fields "$1" 2>/dev/null) || fields=
        if [ -n "$fields" ] && p5_check_recovery "$fields" "$2" "$3"; then printf '%s\n' "$fields"; return; fi
        sleep 1
    done
    p5_fail 'Matching iBEC Recovery did not become ready'
}
p5_dfu_stage() {
    if printf '%s' "$1"|jq -e '.IBFL=="0x1b" and .SRTG=="N/A" and .SRNM=="N/A"' >/dev/null; then printf 'pwned-ibss';
    elif printf '%s' "$1"|jq -e 'has("PWND") or any(.[];contains("PWND:"))' >/dev/null; then printf 'pwned-dfu'; else printf 'rom-dfu'; fi
}
p5_check_pwn_result() {
    local fields=$1 ecid=$2 target=$3 nonce=$4 stage
    p5_check_dfu "$fields" "$ecid" "$target" || { p5_fail 'Exploit returned a different device or left DFU'; return 2; }
    stage=$(p5_dfu_stage "$fields")
    case "$stage" in pwned-dfu|pwned-ibss) ;; *) p5_fail 'Exploit did not reach a pwned DFU/iBSS state'; return 2 ;; esac
    [ "$(printf '%s' "$fields"|jq -r '.NONC//empty')" = "$nonce" ] || { p5_fail 'Nonce changed during checkm8 handoff'; return 2; }
    printf '%s\n' "$stage"
}
p5_prepare_ibss() {
    local bins="$P5_ROOT/bin/macos" ecid=$2 target=$3 ibss=$4 fields stage nonce status n
    fields=$(p5_recovery_fields "$bins") || return $?
    p5_check_dfu "$fields" "$ecid" "$target" || { p5_fail 'Enter matching physical DFU'; return 2; }
    stage=$(p5_dfu_stage "$fields")
    if [ "$stage" = pwned-ibss ]; then
        p5_log 'Device is already in the Legacy-compatible pwned iBSS state; retaining it for the iBEC handoff'
        return 0
    fi
    nonce=$(printf '%s' "$fields"|jq -er .NONC) || return $?
    if [ "$stage" = rom-dfu ]; then
        [ "$(uname -m)" = x86_64 ] || { p5_fail 'Automatic checkm8 currently requires Intel macOS; preload matching pwned iBSS on other hosts'; return 2; }
        p5_run_live 180 "$bins" checkm8 x86_64/ipwnder32 -p --noibss || return $?
        fields=$(p5_recovery_fields "$bins") || return $?
        stage=$(p5_check_pwn_result "$fields" "$ecid" "$target" "$nonce") || return $?
        if [ "$stage" = pwned-ibss ]; then
            p5_log 'iPwnder32 completed the pwned-iBSS handoff directly; keeping this stage for iBEC'
            return 0
        fi
    fi
    if printf '%s' "$fields"|jq -e '(.PWND//"")|ascii_downcase|contains("ipwnder")' >/dev/null; then
        status=0
        p5_run_timeout 60 "$bins" a6-handoff ipwnder-ibss "$bins/lib/libirecovery-1.0.5.dylib" "$ecid" "$(p5_target "$target"|jq -r .board_id)" "$ibss" >&2 || status=$?
        [ "$status" = 0 ] || p5_log "iPwnder returned $status; checking actual handoff"
    else
        p5_run_timeout 30 "$bins" gaster reset >&2 || return $?
        p5_run_timeout 60 "$bins" irecovery -f "$ibss" >&2 || return $?
    fi
    for n in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        fields=$(p5_recovery_fields "$bins" 2>/dev/null) || continue
        p5_check_dfu "$fields" "$ecid" "$target" || return $?
        if [ "$(p5_dfu_stage "$fields")" = pwned-ibss ]; then
            [ "$(printf '%s' "$fields"|jq -r .NONC)" = "$nonce" ] || { p5_fail 'Nonce changed'; return 2; }
            p5_log 'Selected iBSS identity and nonce verified'; return
        fi
    done
    p5_fail 'iBSS did not execute; re-enter DFU'
}
p5_device_lock() {
    local path=${1:-"$HOME/.cache/project5c-native6-device.lock"}
    mkdir -p "$(dirname "$path")" || return $?
    exec 9> "$path"
    p5_native lock-fd 9 || { p5_fail 'Another device operation is running'; return 2; }
}
