#!/usr/bin/env bash
# Device-free regression checks for iPwnder32's A6 handoff states.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/hosttools.sh"

nonce=0123456789abcdef0123456789abcdef01234567
pwned_dfu=$(jq -cn --arg nonce "$nonce" '{MODE:"DFU",ECID:"0x392c210dda8",CPID:"0x8950",BDID:"0xa",NONC:$nonce,PWND:"ipwnder32"}')
pwned_ibss=$(jq -cn --arg nonce "$nonce" '{MODE:"DFU",ECID:"0x392c210dda8",CPID:"0x8950",BDID:"0xa",NONC:$nonce,IBFL:"0x1b",SRTG:"N/A",SRNM:"N/A"}')
rom_dfu=$(jq -cn --arg nonce "$nonce" '{MODE:"DFU",ECID:"0x392c210dda8",CPID:"0x8950",BDID:"0xa",NONC:$nonce,SRTG:"iBoot-1145.3"}')

[ "$(p5_check_pwn_result "$pwned_dfu" 3928855993768 N48AP "$nonce")" = pwned-dfu ]
[ "$(p5_check_pwn_result "$pwned_ibss" 3928855993768 N48AP "$nonce")" = pwned-ibss ]
if p5_check_pwn_result "$rom_dfu" 3928855993768 N48AP "$nonce" >/dev/null 2>&1; then
    p5_fail 'ROM DFU accepted as a successful exploit handoff'; exit 1
fi
if p5_check_pwn_result "$pwned_ibss" 123456 N48AP "$nonce" >/dev/null 2>&1; then
    p5_fail 'Wrong ECID accepted after exploit'; exit 1
fi
if p5_check_pwn_result "$(printf '%s' "$pwned_ibss"|jq '.NONC="ffffffffffffffffffffffffffffffffffffffff"')" 3928855993768 N48AP "$nonce" >/dev/null 2>&1; then
    p5_fail 'Changed nonce accepted after exploit'; exit 1
fi

handoff=no
p5_recovery_fields() {
    if [ "$handoff" = no ]; then printf '%s\n' "$rom_dfu"; else printf '%s\n' "$pwned_ibss"; fi
}
p5_run_live() { handoff=yes; }
p5_prepare_ibss unused 3928855993768 N48AP unused.dfu > /dev/null
[ "$handoff" = yes ] || { p5_fail 'ipwnder32 was not run for ROM DFU'; exit 1; }
p5_log 'pwn stage checks passed: PWND, IBFL handoff, ECID and nonce binding'
