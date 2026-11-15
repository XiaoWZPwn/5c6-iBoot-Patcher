#!/usr/bin/env bash
ex_pick() {
    local title=$1 kind=$2 initial=${3:-} selected status=0 args=()
    if [ "$kind" = directory ]; then args=(--directory); else args=(--kind "$kind"); fi
    selected=$(bash "$ROOT/lib/filepicker.sh" --title "$title" "${args[@]}" -- "$initial") || status=$?
    case "$status" in
        0) REPLY=$selected ;;
        130) p5_log 'Selection cancelled'; return 130 ;;
        3) ask "$title (file picker unavailable; enter path)" "$initial" || return 130
           [ -n "$REPLY" ] || return 130
           case "$REPLY" in '~/'*) REPLY="$HOME/${REPLY#\~/}" ;; esac
           if [ "$kind" = directory ]; then [ -d "$REPLY" ] || return 2; else [ -f "$REPLY" ] || return 2; fi ;;
        *) return "$status" ;;
    esac
}
ex_prepare_choices() {
    ex_identity || return $?
    p5_log "Detected device: $MODEL | ECID: $ECID"
    while :; do
        printf '\nSelect the generated system workspace, project root, or session folder.\nSelect ~/5c6-main/runtime/firmware/[6.1.x]\n' >&2
        ex_pick 'Select generated system project / version workspace / session (Cancel returns to menu)' directory "$SYSTEM" || return $?
        SYSTEM=$REPLY
        if ex_resolve_system; then break; fi
        p5_log 'System folder not accepted. Choose another folder; Cancel returns to the menu.'
    done
    printf '\nSupported: iPhone5,3 / iOS 7.1.2 (11D257).\nSelect iOS 7.x IPSW\n' >&2
    ex_pick 'Select iOS 7.x IPSW' ipsw "$IPSW" || return $?
    IPSW=$REPLY
    printf '\nSelect SHSH matching the connected device ECID and selected IPSW.\nSelect iOS 7.x SHSH\n' >&2
    ex_pick 'Select iOS 7.x SHSH' shsh "$SHSH" || return $?
    SHSH=$REPLY
}
