#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$ROOT/lib/logging.sh"
if [ "${PATCHER_LOG_CHILD:-no}" != yes ]; then
    case "${1:-menu}" in help|--help|-h) ;; *)
        patcher_logged_run "$ROOT/tools/untethered.sh" "$@"
        exit $? ;;
    esac
fi
source "$ROOT/lib/exploit.sh"
COMMAND=${1:-menu}; [ "$#" = 0 ] || shift
IPSW= SHSH= KEYS= ECID= SYSTEM= WORK= EXECUTE=no
KIT="$ROOT/resources/kit"
usage() {
    cat <<'USAGE'
5c6 iBoot Patcher — Untethered boot only / N48 / 7.1.2 signed base
bash tools/untethered.sh menu
bash tools/untethered.sh prepare --ipsw PATH --shsh PATH [--system-work PATH] [--ecid NUMBER] [--keys JSON] [--work PATH]
bash tools/untethered.sh nor|install|reboot --execute [--work PATH]
bash tools/untethered.sh inspect --execute [--work PATH]
bash tools/untethered.sh finish --execute [--work PATH]  # Install, Verify & Reboot
bash tools/untethered.sh verify
bash tools/untethered.sh ramdisk [--ramdisk-dir PATH | --ramdisk-url HTTPS_URL]
--ramdisk-dir / --ramdisk-url also work with install and inspect.
prepare auto-detects device ECID unless --ecid is supplied for offline preparation.
Choose an EXTERNAL generated system workspace; result.json is not required.
Untethered files default to runtime/Untethered/<decimal ECID>/; no folder selection needed.
nor writes signed boot NOR only. Enter pwned-iBSS again before install.
install writes tail partitions and startup payloads; reboot sets NVRAM last and calls reboot_bak.
inspect boots SSH RAM and reads installed state. No --execute means preview, no USB access.
Other iOS 7.x builds are identified but refused until a matching exploit profile is verified.
USAGE
}
while [ "$#" -gt 0 ]; do
    case "$1" in --execute) EXECUTE=yes; shift; continue ;; --help|-h) usage; exit ;; esac
    [ "$#" -ge 2 ] || { usage; exit 2; }
    case "$1" in --ramdisk-dir) P5_SSHRD_DIR=$2 ;; --ramdisk-url) P5_SSHRD_URL=$2 ;; --ipsw) IPSW=$2 ;; --shsh) SHSH=$2 ;; --keys) KEYS=$2 ;; --ecid) ECID=$2 ;; --system-work) SYSTEM=$2 ;; --work) WORK=$2 ;; *) p5_fail "Unknown option: $1"; exit 2 ;; esac
    shift 2
done
case "$COMMAND" in help|--help|-h) usage; exit ;; menu|prepare|nor|install|inspect|reboot|finish|verify|ramdisk) ;; *) usage; exit 2 ;; esac
[ "$(uname -s)" = Darwin ] || { p5_fail 'This bundled release requires macOS'; exit 2; }
patcher_log_context
ex_verify
if [ "$COMMAND" = verify ]; then p5_log 'Resource checksums passed'; exit; fi
if [ "$COMMAND" = ramdisk ]; then p5_sshrd_ensure "$KIT"; p5_log 'SSH ramdisk cache verified'; exit; fi
case "$COMMAND" in
    nor|finish)
        if [ "$EXECUTE" = yes ]; then
            source "$ROOT/lib/dfu-guide.sh"
            patcher_dfu_guide "$COMMAND"
        fi ;;
esac
if [ "$COMMAND" = menu ]; then
    [ -t 0 ] || { p5_fail 'Interactive menu requires a terminal'; exit 2; }
    ask() { printf '%s [%s]: ' "$1" "$2"; IFS= read -r REPLY || return 1; REPLY=${REPLY:-$2}; }
    source "$ROOT/lib/untethered-ui.sh"
    select_option() { CHOICE=$(bash "$ROOT/lib/menu.sh" "$@") || return $?; }
    while :; do
        COMMAND=menu
        ECID= SYSTEM= WORK= EXECUTE=no
        select_option $'5c6 iBoot Patcher\n- Tools by XiaoWZ and GPT-6.1 Sol -\n@Peterdobby for the "iBoot Patch"\n@MC-XiaoXiao provided "5c6"' 'Prepare Exploit iBoot / NOR' 'Write boot NOR' 'Install, Verify & Reboot' 'Back' || exit 0
        case "$CHOICE" in
            0) COMMAND=prepare
               patcher_log_context
               if ! ex_prepare_choices; then
                   p5_log 'Preparation selection stopped; returning to menu.'
                   continue
               fi ;;
            1) COMMAND=nor ;; 2) COMMAND=finish ;; *) exit ;;
        esac
        operation_args=("$COMMAND")
        if [ "$COMMAND" = prepare ]; then
            operation_args+=(--ipsw "$IPSW" --shsh "$SHSH" --ecid "$ECID" --system-work "$SYSTEM")
            [ -z "$KEYS" ] || operation_args+=(--keys "$KEYS")
        else
            operation_args+=(--execute)
        fi
        [ -z "${P5_SSHRD_DIR:-}" ] || operation_args+=(--ramdisk-dir "$P5_SSHRD_DIR")
        [ -z "${P5_SSHRD_URL:-}" ] || operation_args+=(--ramdisk-url "$P5_SSHRD_URL")
        operation_status=0
        # Separate operations retain strict error handling and their own cleanup
        # traps; the menu stays alive after success, cancellation or failure.
        PATCHER_LOG_CHILD=no bash "$ROOT/tools/untethered.sh" "${operation_args[@]}" || operation_status=$?
        printf '\nOperation %s finished (exit %s). Returning to 5c6 iBoot Patcher menu.\n' "$COMMAND" "$operation_status"
    done
fi
if [ -z "$WORK" ]; then
    [ -n "$ECID" ] || ex_identity
    ex_device_workspace
fi
WORK=$(p5_abs "$WORK")
patcher_log_context
if [ "$COMMAND" = prepare ]; then
    [ -n "$ECID" ] || ex_identity
    [[ "$ECID" =~ ^(0x[0-9a-fA-F]+|[1-9][0-9]*)$ ]] || { p5_fail 'Invalid ECID'; exit 2; }
    MODEL=iPhone5,3
    ex_resolve_system
    ECID=$((ECID)); IPSW=$(p5_abs "$IPSW"); SHSH=$(p5_abs "$SHSH"); SYSTEM=$(p5_abs "$SYSTEM")
    [ -z "$KEYS" ] || KEYS=$(p5_abs "$KEYS")
    ex_system_check
    [ ! -e "$WORK/config.json" ] && [ ! -e "$WORK/nor" ] || { p5_fail 'This device already has prepared files; use its existing operations or choose a new --work directory'; exit 2; }
    mkdir -p "$WORK"
    ex_import_system
    patcher_log_context
    ex_prepare; ex_package
    jq -n --argjson ecid "$ECID" '{ecid:$ecid,system_workspace:"installed-system"}' > "$WORK/config.json"
    p5_log "Prepared: $WORK. Next: nor --execute (automatically matches connected device)"
    exit
fi
[ -f "$WORK/config.json" ] || { p5_fail 'Run prepare first in this workspace'; exit 2; }
EXPECTED=$(jq -er .ecid "$WORK/config.json"); SYSTEM=$(jq -er .system_workspace "$WORK/config.json")
case "$SYSTEM" in /*) ;; *) SYSTEM=$(p5_relative "$WORK" "$SYSTEM") ;; esac
patcher_log_context
if [ "$EXECUTE" != yes ]; then p5_log "Preview: $COMMAND in $WORK; add --execute for device access"; exit; fi
ex_identity
[ "$ECID" = "$EXPECTED" ] || { p5_fail 'Connected ECID differs from prepared workspace'; exit 2; }
patcher_log_context
ex_system_check
p5_asset_verify "$WORK/base" iPhone5,3 "$ECID"
p5_device_lock
mkdir -p "$WORK/runs"
RUN=$(mktemp -d "$WORK/runs/$(date +%Y%m%d-%H%M%S)-$COMMAND.XXXXXX")
if [ -n "${PATCHER_LOG_SESSION:-}" ]; then
    printf '%s\n' "$RUN" > "$PATCHER_LOG_SESSION/evidence-path.txt"
fi
trap 'ex_proxy_stop' EXIT
case "$COMMAND" in nor) ex_nor ;; inspect) ex_inspect ;; install) ex_install ;; reboot) ex_reboot ;; finish) ex_finish ;; esac
p5_log "Completed $COMMAND; evidence: $RUN"
