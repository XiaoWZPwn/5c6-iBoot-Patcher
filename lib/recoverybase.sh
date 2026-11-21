#!/usr/bin/env bash
# Shared, relocatable N48/7.1.2 assets. Bash controls all operations.
source "$(dirname -- "${BASH_SOURCE[0]}")/hosttools.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/sshrd.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/pmgr.sh"
P5_UNTETHERED_BOOTARGS='rd=disk0s1s1 -v amfi=0xff amfi_get_out_of_my_way=1 cs_enforcement_disable=1 pio-error=0'
P5_RDH_SHA=22d7de5f9b6e2db4a9e6805018698e43c6d3870f266129dbc98ac09bf8a13352
p5_kit_bins() {
    local kit=$1 platform="linux/$P5_ARCH"
    [ "$(uname -s)" != Darwin ] || platform=macos
    [ -d "$kit/bin/$platform" ] || { p5_fail 'Select a complete Legacy iOS Kit directory with native tools'; return 2; }
    printf '%s\n' "$kit/bin/$platform"
}
p5_feature_host() {
    local bins=$1 host="$1/idevicerestore-nor" version
    version=$(p5_run_timeout 15 "$bins" "$host" --version) || return $?
    [[ "$version" = *native6-5c-features-r3* ]] || { p5_fail 'Feature host revision differs'; return 2; }
    printf '%s\n' "$host"
}
p5_asset_verify() {
    local dir=$1 model=$2 ecid=$3 name digest
    p5_pmgr_iboot_check "$dir/iBoot.patched" || return $?
    jq -e --arg model "$model" --argjson ecid "$((ecid))" '.schema==1 and .model==$model and .ecid==$ecid and .base_build=="11D257" and (.files|type)=="object" and (.files|length)>=6 and (.files|all(.[];type=="string" and test("^[a-f0-9]{64}$")))' "$dir/assets.json" >/dev/null || return $?
    while IFS=$'\t' read -r name digest; do
        p5_relative "$dir" "$name" >/dev/null || return $?
        [ "$(p5_sha "$dir/$name")" = "$digest" ] || { p5_fail "Base asset changed: $name"; return 2; }
    done < <(jq -r '.files|to_entries[]|[.key,.value]|@tsv' "$dir/assets.json")
}
p5_base_assets() (
    local bins=$1 kit=$2 ipsw=$3 shsh=$4 out=$5 model=$6 ecid=$7 keys=${8:-} identity manifest json json_keys validate board=n48ap path file iv key status=0 hashes='{}' rel P5_TMP=''
    [ "$model" = iPhone5,3 ] || { p5_fail 'The tested 7.1.2 feature path currently supports N48 only'; return 2; }
    if [ -f "$out/assets.json" ]; then
        p5_asset_verify "$out" "$model" "$ecid" || return $?
        if [ -n "$shsh" ]; then
            [ "$(jq -r '.inputs.shsh_sha256//empty' "$out/assets.json")" = "$(p5_sha "$shsh")" ] || { p5_fail 'Selected SHSH differs from this prepared base; choose a new workspace'; return 2; }
        fi
        if [ -n "$ipsw" ]; then
            p5_temp || return $?; p5_zip_member "$ipsw" BuildManifest.plist "$P5_TMP/selected-manifest" || return $?
            [ "$(p5_sha "$P5_TMP/selected-manifest")" = "$(p5_sha "$out/BuildManifest.plist")" ] || { p5_fail 'Selected base firmware differs from this prepared workspace'; return 2; }
        fi
        printf '%s\n' "$out"; return
    fi
    [ ! -e "$out" ] || { p5_fail 'Incomplete base assets retained; select a new workspace'; return 2; }
    p5_require_tools "$bins" xpwntool iBoot32Patcher hfsplus
    local kbins; kbins=$(p5_kit_bins "$kit") || return $?; p5_require_tools "$kbins" validate
    [ -f "$ipsw" ] && [ -f "$shsh" ] || { p5_fail 'Select native iPhone5,3 7.1.2 IPSW and its device SHSH'; return 2; }
    p5_output_temp "$out" || return $?; mkdir -p "$out/nor"
    p5_zip_member "$ipsw" BuildManifest.plist "$out/BuildManifest.plist" || return $?
    manifest=$(p5_plist "$out/BuildManifest.plist") || return $?
    identity=$(printf '%s' "$manifest" | jq -ce 'select(.ProductVersion=="7.1.2" and .ProductBuildVersion=="11D257" and (.SupportedProductTypes|type)=="array" and (.SupportedProductTypes|index("iPhone5,3"))!=null)|[.BuildIdentities[]|select(.Info.DeviceClass=="n48ap" and (.Info.Variant|contains("Erase")))]|if length==1 then .[0] else error("Native base identity differs") end') || return $?
    if [ "$(p5_native hex-range "$shsh" 0 2)" = 1f8b ]; then gzip -dc "$shsh" > "$P5_TMP/shsh.plist" || return $?; else cp "$shsh" "$P5_TMP/shsh.plist"; fi
    validate=$(p5_run_timeout 30 "$kbins" validate "$P5_TMP/shsh.plist" "$out/BuildManifest.plist") || return $?
    local expected; printf -v expected '0x%016x' "$((ecid))"
    printf '%s\n' "$validate" > "$out/shsh-validation.txt"
    printf '%s' "$validate" | grep -Fiq "seems usable for ECID $expected" || { p5_fail 'Base SHSH does not validate for the connected device'; return 2; }
    json=$(p5_plist "$P5_TMP/shsh.plist") || return $?
    printf '%s' "$json" | jq -e '(.APTicket["$data"]|type)=="string" and (.LLB.Blob["$data"]|type)=="string"' >/dev/null || return $?
    p5_native hex-write "$(printf '%s' "$json"|jq -r '.APTicket["$data"]')" "$out/apticket.der" || return $?
    [ "$(p5_size "$out/apticket.der")" -ge 500 ] || return 2
    p5_native img3-wrap "$kit/resources/firmware/src/scab_template.img3" "$out/apticket.der" "$out/SCAB.img3" plaintext || return $?
    p5_native img3-data "$out/SCAB.img3" "$P5_TMP/ticket-readback"; cmp "$out/apticket.der" "$P5_TMP/ticket-readback" || return $?
    for name in iBoot LLB; do
        path=$(printf '%s' "$identity"|jq -r --arg name "$name" '.Manifest[$name].Info.Path')
        p5_zip_member "$ipsw" "$path" "$out/nor/${path##*/}" || return $?
    done
    local flash; flash=$(printf '%s' "$identity"|jq -r '.Manifest.LLB.Info.Path|split("/")|.[0:-1]|join("/")')
    while IFS= read -r path; do
        case "$path" in "$flash"/*) [ "${path%/}" = "$path" ] || continue; p5_zip_member "$ipsw" "$path" "$out/nor/${path##*/}" || return $? ;; esac
    done < <(p5_native zip-list "$ipsw")
    file=$(printf '%s' "$identity"|jq -r '.Manifest.iBoot.Info.Path|split("/")|last')
    if [ -z "$keys" ] && [ -f "$P5_ROOT/resources/profiles/iBoot.n48.11D257.raw" ]; then
        [ "$(p5_sha "$out/nor/$file")" = 7d11f09f64bc948b52c2e006a369697a16b94443d0c4aa8ac2c7b8cd12170ec8 ] || { p5_fail 'IPSW iBoot differs from offline profile'; return 2; }
        [ "$(p5_sha "$P5_ROOT/resources/profiles/iBoot.n48.11D257.raw")" = 7f7abf8119116601a98035fe566def4757a8a4557ea602074c77af82692114a0 ] || return 2
        cp "$P5_ROOT/resources/profiles/iBoot.n48.11D257.raw" "$out/iBoot.raw"
    else
        if [ -n "$keys" ]; then json_keys=$(cat "$keys") || return $?; else json_keys=$(bash "$P5_LIB/firmwarekeys.sh" --model "$model" --version 7.1.2 --build 11D257 --components iBoot) || return $?; fi
        iv=$(printf '%s' "$json_keys"|jq -er '.iBoot.iv') || return $?; key=$(printf '%s' "$json_keys"|jq -er '.iBoot.key') || return $?
        p5_native img3-data "$out/nor/$file" "$out/iBoot.raw" "$iv" "$key" || return $?
    fi
    LC_ALL=C grep -aFq iBoot-1940.10.58 "$out/iBoot.raw" || { p5_fail 'Wrong normal 7.1.2 iBoot'; return 2; }
    p5_run_timeout 60 "$bins" iBoot32Patcher "$out/iBoot.raw" "$out/iBoot.patched" --rsa --debug --boot-partition --boot-ramdisk -b "$P5_UNTETHERED_BOOTARGS" > "$out/iboot-patch.log" 2>&1 || status=$?
    [ "$status" -le 1 ] && grep -q 'main: Quitting' "$out/iboot-patch.log" || return 2
    while read -r at bytes; do [ "$(p5_native hex-range "$out/iBoot.patched" "$at" 4)" = "$bytes" ] || return 2; done <<'CHECKS'
0x1b0d8 00201860
0xa7c 00200020
0xb24 00200020
0x1bbec 01200120
CHECKS
    p5_pmgr_iboot_patch "$out/iBoot.patched" "$out/iBoot.patched" || return $?
    p5_native img3-create ibec "$out/iBoot.patched" "$out/iBEC" || return $?
    printf '%s' "$json" | jq --argjson ecid "$((ecid))" '{ECID:$ecid,BaseVersion:"7.1.2",BaseBuild:"11D257",LLB}' > "$out/meta.json"
    local scab; scab=$(p5_native hex-range "$out/SCAB.img3" 0 "$(p5_size "$out/SCAB.img3")")
    p5_json_update "$out/meta.json" --arg scab "$scab" '.SCAB={"$data":$scab}'
    while IFS= read -r file; do rel=${file#"$out/"}; hashes=$(printf '%s' "$hashes"|jq --arg rel "$rel" --arg sha "$(p5_sha "$file")" '.[$rel]=$sha'); done < <(find "$out" -type f)
    jq -n --arg model "$model" --argjson ecid "$((ecid))" --argjson hashes "$hashes" --arg shsh_sha "$(p5_sha "$shsh")" '{schema:1,model:$model,ecid:$ecid,base_build:"11D257",files:$hashes,inputs:{shsh_sha256:$shsh_sha}}' > "$out/assets.json"
    printf '%s\n' "$out"
)
p5_kit_ramboot() (
    local kit=$1 bins=$2 ecid=$3 model=$4 logdir=$5 cache kbins fields stage file command start now probe bootstrap_ibss=${6:-}
    cache="$kit/saved/$model/ramdisk_11D257/saved"
    p5_sshrd_ensure "$kit" || return $?
    for file in iBSS iBEC Ramdisk.dmg DeviceTree.dec Kernelcache.dec; do
        [ -s "$cache/$file" ] || { p5_fail "Legacy iOS Kit SSH ramdisk cache is missing $file"; return 2; }
    done
    kbins=$(p5_kit_bins "$kit") || return $?
    fields=$(p5_recovery_fields "$kbins" 2>/dev/null) || fields=
    if [ -n "$fields" ] && p5_check_recovery "$fields" "$ecid" N48AP >/dev/null 2>&1; then
        p5_log 'Resume Kit SSH ramdisk boot from matching Recovery'
    else
        p5_prepare_ibss "$kbins" "$ecid" N48AP "${bootstrap_ibss:-$cache/iBSS}" || return $?
        p5_log 'Boot matching Legacy iOS Kit SSH ramdisk'
        p5_run_timeout 60 "$kbins" irecovery -f "$cache/iBEC" >&2 || return $?
        fields=$(p5_wait_recovery "$kbins" "$ecid" N48AP) || return $?
    fi
    for file in Ramdisk.dmg DeviceTree.dec Kernelcache.dec; do
        case "$file" in Ramdisk.dmg) command=ramdisk ;; DeviceTree.dec) command=devicetree ;; Kernelcache.dec) command=bootx ;; esac
        p5_run_timeout 120 "$kbins" irecovery -f "$cache/$file" >&2 || return $?
        p5_run_timeout 60 "$kbins" irecovery -c "$command" >&2 || return $?
        sleep 2 || return $?
    done
    start=$(date +%s)
    while ! probe=$(p5_native restored-probe "$((ecid))" N48AP --protocol 13 2>/dev/null); do
        now=$(date +%s)
        [ "$((now-start))" -lt 90 ] || { p5_fail 'Kit SSH ramdisk did not expose restored service'; return 2; }
        sleep 1 || return $?
    done
    printf '%s\n' "$probe" > "$logdir/kit-ramboot-probe.json"
    printf '%s\n' "$probe"
)
p5_ssh_setup() {
    local kit=$1 port=$2 work=$3 kbins
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { p5_fail 'Invalid SSH port'; return 2; }
    kbins=$(p5_kit_bins "$kit") || return $?; p5_require_tools "$kbins" sshpass
    mkdir -p "$work"
    P5_SSH=("$kbins/sshpass" -eSSHPASS ssh -F /dev/null -p "$port" -o "UserKnownHostsFile=\"$work/known_hosts\"" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 -o ConnectTimeout=5 root@127.0.0.1)
    export SSHPASS=${SSHPASS:-alpine}
}
p5_ssh_setup_direct() {
    local kit=$1 port=$2 work=$3 key=$4 kbins sshbin
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { p5_fail 'Invalid SSH port'; return 2; }
    kbins=$(p5_kit_bins "$kit") || return $?; p5_require_tools "$kbins" sshpass
    sshbin=$(command -v ssh) || { p5_fail 'Host SSH client is missing'; return 2; }
    [ -s "$key" ] || { p5_fail 'Direct Restore RAM SSH key is missing'; return 2; }
    mkdir -p "$work"
    P5_SSH=("$sshbin" -F /dev/null -p "$port" -i "$(p5_abs "$key")" -o IdentitiesOnly=yes -o "UserKnownHostsFile=$work/known_hosts" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=yes -o PreferredAuthentications=publickey -o NumberOfPasswordPrompts=0 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1 -o ConnectTimeout=5 root@127.0.0.1)
}
p5_ssh() { "${P5_SSH[@]}" "$@"; }
