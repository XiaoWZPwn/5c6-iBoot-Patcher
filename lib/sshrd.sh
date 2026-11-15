#!/usr/bin/env bash
# Optional, verified SSH RAM cache. No USB access in these functions.
p5_sshrd_verify() {
    local dir=$1 name sha
    while IFS=$'\t' read -r name sha; do
        [ -f "$dir/$name" ] && [ ! -L "$dir/$name" ] && [ "$(p5_sha "$dir/$name")" = "$sha" ] || return 2
    done < <(jq -r 'to_entries[]|[.key,.value]|@tsv' "$P5_ROOT/resources/sshrd-profile.json")
}
p5_sshrd_ensure() (
    local dest="$1/saved/iPhone5,3/ramdisk_11D257/saved" source=${P5_SSHRD_DIR:-} url=${P5_SSHRD_URL:-} stage name
    p5_sshrd_verify "$dest" && return 0
    if [ -z "$source$url" ] && [ -t 0 ]; then
        local choice
        choice=$(bash "$P5_ROOT/lib/menu.sh" 'SSH ramdisk dependency' 'Import prepared component folder' 'Download verified archive from HTTPS URL' 'Back') || return $?
        case "$choice" in
            0) printf 'Component folder (iBSS/iBEC/Ramdisk.dmg/DeviceTree.dec/Kernelcache.dec): ' >&2; IFS= read -r source || return 2 ;;
            1) printf 'HTTPS archive URL: ' >&2; IFS= read -r url || return 2 ;;
            *) return 2 ;;
        esac
    fi
    if [ -z "$source$url" ]; then
        p5_fail "SSH ramdisk missing or changed. Put the five verified components in $dest, use --ramdisk-dir PATH, or configure --ramdisk-url HTTPS_URL. See README.md."
        return 2
    fi
    mkdir -p "${dest%/*}"
    stage=$(mktemp -d "${dest%/*}/.download.XXXXXX") || return $?
    trap 'rm -rf -- "$stage"' EXIT
    if [ -n "$source" ]; then
        p5_sshrd_verify "$source" || { p5_fail 'Imported SSH ramdisk does not match the verified N48/11D257 profile'; return 2; }
        for name in iBSS iBEC Ramdisk.dmg DeviceTree.dec Kernelcache.dec; do cp "$source/$name" "$stage/$name" || return $?; done
    else
        case "$url" in https://*) ;; *) p5_fail 'SSH ramdisk URL must use HTTPS'; return 2 ;; esac
        p5_log 'Download optional SSH ramdisk archive'
        curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 300 --max-filesize 134217728 --retry 2 --output "$stage/archive.tar" "$url" || return $?
        # Extract only named regular files to stdout; never unpack archive paths,
        # permissions, links or extra entries into the project.
        for name in iBSS iBEC Ramdisk.dmg DeviceTree.dec Kernelcache.dec; do
            (ulimit -f 131072; bsdtar -xOf "$stage/archive.tar" "$name") > "$stage/$name" || return $?
        done
    fi
    p5_sshrd_verify "$stage" || { p5_fail 'SSH ramdisk SHA-256 validation failed; cache not installed'; return 2; }
    # Keep an existing incomplete cache for inspection; only replace known files.
    mkdir -p "$dest"
    for name in iBSS iBEC Ramdisk.dmg DeviceTree.dec Kernelcache.dec; do mv "$stage/$name" "$dest/$name" || return $?; done
    p5_sshrd_verify "$dest"
)
