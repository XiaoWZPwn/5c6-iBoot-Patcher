#!/usr/bin/env bash
# Stubbed probes only. Never opens USB or performs a timed wait.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/exploit.sh"
source "$ROOT/lib/dfu-guide.sh"
WORK= ECID=3928855993768
if [ "${1:-}" = --interactive ]; then
    p5_recovery_fields() { printf '{"MODE":"Recovery"}\n'; }
    ex_identity() { ECID=3928855993768; }
    checks=0
    patcher_dfu_ready() { checks=$((checks+1)); [ "$checks" -gt 1 ]; }
    sleep() { :; }
    patcher_dfu_guide nor
    [ "$checks" = 2 ]
    exit
fi
probe='{"MODE":"DFU","ECID":"3928855993768","CPID":"0x8950","BDID":"0xa"}'
p5_recovery_fields() { printf '%s\n' "$probe"; }
patcher_dfu_guide nor
probe=$(printf '%s' "$probe"|jq '.ECID="123"')
if patcher_dfu_guide nor; then p5_fail 'Wrong DFU ECID accepted'; exit 1; fi
p5_native() { printf '{"model":"iPhone5,3","ecid":3928855993768}\n'; }
patcher_dfu_guide finish
probe='{"MODE":"Recovery","ECID":"3928855993768"}'
if patcher_dfu_guide nor < /dev/null; then p5_fail 'Noninteractive Recovery accepted as DFU'; exit 1; fi
sleep() { :; }
patcher_countdown 'Test countdown:' 3
p5_log 'DFU guide checks passed: DFU reuse, wrong ECID rejection, running SSH RAM reuse and noninteractive refusal'
