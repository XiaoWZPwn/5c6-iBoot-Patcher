#!/usr/bin/env bash
# iPhone 5c physical-button guide; no reboot/NVRAM/flash commands.
patcher_dfu_ready() {
    local fields
    fields=$(p5_recovery_fields "$P5_TOOLS" 2>/dev/null) || return 1
    [ "$(printf '%s' "$fields"|jq -r '.MODE//""')" = DFU ] || return 1
    local actual
    actual=$(printf '%s' "$fields"|jq -er .ECID) || return 2
    p5_check_dfu "$fields" "${GUIDE_ECID:-$actual}" N48AP || { p5_fail 'DFU device identity differs; connect the target iPhone5,3 only'; return 2; }
    GUIDE_ECID=$((actual))
    return 0
}
patcher_countdown() {
    local label=$1 seconds=$2 remaining
    for ((remaining=seconds; remaining>0; remaining--)); do
        printf '\r%s %2s seconds remaining. ' "$label" "$remaining" >&2
        sleep 1
    done
    printf '\n' >&2
}
patcher_dfu_guide() {
    local operation=$1 fields mode='' seconds=10 answer status n
    GUIDE_ECID=${ECID:-}
    if [ -n "${WORK:-}" ] && [ -f "$WORK/config.json" ]; then
        GUIDE_ECID=$(jq -er .ecid "$WORK/config.json") || return $?
    fi
    if [ "$operation" = finish ]; then
        local probe
        if probe=$(p5_native restored-identity --protocol 13 2>/dev/null); then
            [ "$(printf '%s' "$probe"|jq -r .model)" = iPhone5,3 ] || return 2
            local ram_ecid
            ram_ecid=$(printf '%s' "$probe"|jq -er .ecid) || return $?
            [ -z "$GUIDE_ECID" ] || [ "$((GUIDE_ECID))" = "$((ram_ecid))" ] || return 2
            p5_log 'Matching SSH ramdisk is already running; DFU guide skipped'
            return 0
        fi
    fi
    status=0
    patcher_dfu_ready || status=$?
    case "$status" in 0) p5_log 'Target device is already in DFU; continuing'; return ;; 2) return 2 ;; esac
    [ -t 0 ] || { p5_fail 'Enter physical DFU and retry, or run the interactive menu for the timed DFU guide'; return 2; }
    fields=$(p5_recovery_fields "$P5_TOOLS" 2>/dev/null) || fields='{}'
    mode=$(printf '%s' "$fields"|jq -r '.MODE//""')
    # Bind to an attached device before it temporarily disconnects.
    if [ -z "$GUIDE_ECID" ] && ex_identity; then GUIDE_ECID=$ECID; fi
    while :; do
        printf '\nDFU Mode Guide — iPhone 5c\nKeep the USB cable connected. DFU has a completely black screen.\nTOP/POWER is the button on the top edge; HOME is below the display.\n' >&2
        printf 'Press Enter when ready to start, or type q to return to the menu: ' >&2
        IFS= read -r answer || return 130
        case "$answer" in q|Q) return 130 ;; esac
        patcher_countdown 'Get ready:' 3
        seconds=10
        [ "$mode" != Recovery ] || seconds=8
        printf '\nStep 1: Press and HOLD TOP/POWER + HOME now.\n' >&2
        patcher_countdown 'Hold TOP/POWER + HOME:' "$seconds"
        printf '\nStep 2: RELEASE TOP/POWER; KEEP HOLDING HOME.\n' >&2
        patcher_countdown 'Keep holding HOME:' 8
        printf '\nChecking DFU. Keep holding HOME until detection completes...\n' >&2
        for n in 1 2 3 4 5; do
            status=0
            patcher_dfu_ready || status=$?
            case "$status" in
                0) printf 'DFU detected. Release HOME.\n' >&2; ECID=$GUIDE_ECID; MODEL=iPhone5,3; return 0 ;;
                2) return 2 ;;
            esac
            sleep 1
        done
        printf 'DFU not detected. If the Apple logo or iTunes icon is visible, retry the timing.\nRetry? [Y/n]: ' >&2
        IFS= read -r answer || return 130
        case "$answer" in n|N|q|Q) return 130 ;; esac
        mode=''
    done
}
