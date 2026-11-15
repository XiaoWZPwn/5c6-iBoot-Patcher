#!/usr/bin/env bash
# An outer Bash owns tee and its FIFO; inner firmware helpers may use EXIT
# traps independently. stdin stays attached to the terminal for menus/SSH.
patcher_logged_run() (
    local script=$1; shift
    local root session fifo tee_pid child_pid='' status=0 started command=${1:-menu}
    root=$(CDPATH= cd -- "$(dirname "$script")/.." && pwd -P) || exit $?
    mkdir -p "$root/runtime/logs" || exit $?
    session=$(mktemp -d "$root/runtime/logs/$(date '+%Y%m%d-%H%M%S').XXXXXX") || exit $?
    fifo="$session/output.pipe"
    started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    mkfifo -m 600 "$fifo" || exit $?
    exec 3>&1 4>&2
    (trap '' INT TERM; exec tee "$session/output.log" < "$fifo" 3>&- 4>&-) & tee_pid=$!
    exec > "$fifo" 2>&1
    finish_logging() {
        local code=$?
        trap - EXIT INT TERM
        printf '[%s] [RESULT] exit=%s | Log: %s/output.log\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$code" "$session"
        jq -n --arg command "$command" --arg started "$started" --arg finished "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --argjson code "$code" \
            '{requested_command:$command,started_at:$started,finished_at:$finished,exit_code:$code,output:"output.log",context:"context.json"}' > "$session/result.json" || :
        exec 1>&3 2>&4
        wait "$tee_pid" || printf '[WARN] Log writer failed: %s\n' "$session" >&2
        unlink "$fifo"
        exec 3>&- 4>&-
        exit "$code"
    }
    trap finish_logging EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '[%s] [STEP] Start %s. Log: %s/output.log\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$command" "$session"
    PATCHER_LOG_CHILD=yes PATCHER_LOG_SESSION="$session" bash "$script" "$@" || status=$?
    exit "$status"
)
patcher_log_context() {
    [ -n "${PATCHER_LOG_SESSION:-}" ] || return 0
    jq -n --arg operation "${COMMAND:-}" --arg ecid "${ECID:-}" --arg workspace "${WORK:-}" --arg system "${SYSTEM:-}" --arg execute "${EXECUTE:-no}" \
        '{operation:$operation,ecid:$ecid,workspace:$workspace,installed_system_inputs:$system,execute:($execute=="yes")}' > "$PATCHER_LOG_SESSION/context.json"
}
