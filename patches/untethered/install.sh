#!/bin/bash
# Streamed into immutable Kit RAM. All geometry arguments originate from readback.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
set -eE -o pipefail
cd /
[ "$#" = 12 ] || exit 2
mode=$1; sysfirst=$2; syslast=$3; datafirst=$4; oldend=$5; newend=$6; guid=$7; bytes=$8; expfirst=$9; explast=${10}; bootfirst=${11}; bootlast=${12}
case "$mode" in --check|--install) ;; *) exit 2 ;; esac
for number in "$sysfirst" "$syslast" "$datafirst" "$oldend" "$newend" "$bytes" "$expfirst" "$explast" "$bootfirst" "$bootlast"; do [[ "$number" =~ ^[0-9]+$ ]] || exit 2; done
[[ "$guid" =~ ^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$ ]] || exit 2
[ "$sysfirst" = 6 ] && [ "$((syslast+1))" = "$datafirst" ] && [ "$((oldend-newend))" = 2176 ] &&
    [ "$((newend+1))" = "$expfirst" ] && [ "$((explast-expfirst+1))" = 128 ] &&
    [ "$((explast+1))" = "$bootfirst" ] && [ "$((bootlast-bootfirst+1))" = 2048 ] && [ "$bootlast" = "$oldend" ] &&
    [ "$bytes" = "$(((newend-datafirst+1)*4096))" ] || exit 2
query() { printf 'i\n%s\nq\n' "$1" | gptfdisk /dev/rdisk0s1; }
range() {
    local info fr='First sector: ([0-9]+)' lr='Last sector: ([0-9]+)' first last
    info=$(query "$1"); [[ "$info" =~ $fr ]] || exit 2; first=${BASH_REMATCH[1]}; [[ "$info" =~ $lr ]] || exit 2; last=${BASH_REMATCH[1]}
    [ "$first" = "$2" ] && [ "$last" = "$3" ] || exit 2
}
range 1 "$sysfirst" "$syslast"
info=$(query 2); gr='Partition unique GUID: ([A-Fa-f0-9-]+)'; lr='Last sector: ([0-9]+)'; fr='First sector: ([0-9]+)'; flags='Attribute flags: ([A-Fa-f0-9]+)'
[[ "$info" =~ $gr ]] && [ "${BASH_REMATCH[1]}" = "$guid" ] || exit 2
[[ "$info" =~ $fr ]] && [ "${BASH_REMATCH[1]}" = "$datafirst" ] || exit 2
[[ "$info" =~ $flags ]] || exit 2; case "${BASH_REMATCH[1]}" in 0001000000000000|0003000000000000) ;; *) exit 2 ;; esac
[[ "$info" =~ $lr ]] || exit 2; current=${BASH_REMATCH[1]}
case "$current" in "$oldend"|"$newend") ;; *) exit 2 ;; esac
if [ "$mode" = --check ]; then echo INSTALL_SHELL_CHECK_PASSED; exit; fi
if [ "$current" = "$oldend" ]; then
    [ ! -e /dev/disk0s1s3 ] && [ ! -e /dev/disk0s1s4 ] || exit 2
    hfs_resize /mnt2 "$bytes"
    /usr/bin/umount_helper
    printf 'd\n2\nn\n\n%s\n\nc\n2\nData\nx\na\n2\n48\n49\n\nc\n2\n%s\ns\n4\nm\nn\n3\n\n%s\n\nn\n4\n\n%s\n\nw\nY\n' "$newend" "$guid" "$explast" "$bootlast" | gptfdisk /dev/rdisk0s1
else
    range 3 "$expfirst" "$explast"; range 4 "$bootfirst" "$bootlast"
fi
echo GPT_WRITE_FINISHED
