#!/usr/bin/env bash
#
# SYNOPSIS
#     Единственная точка исполнения внешних команд и записи файлов.
#
# DESCRIPTION
#     Тот же приём, что в LinuxConfigurator: шаги не зовут утилиты напрямую.
#     В dry-run команда не исполняется, а уходит в журнал операций вместе с
#     точной командной строкой; запись файла заменяется строкой журнала.
#     Без dry-run команда исполняется и логируется как обычно.

run_exec() {
    local category="$1"; shift
    local pretty="$*"
    if (( LRI_DRY_RUN )); then
        log_journal "$category" exec "$pretty" "dry-run"
        log_debug "dry-run: $pretty"
        return 0
    fi
    log_journal "$category" exec "$pretty" "real"
    log_info "exec: $pretty"
    "$@"
}

run_write_file() {
    local category="$1" path="$2" content="$3"
    if (( LRI_DRY_RUN )); then
        log_journal "$category" write "$path" "$(wc -c <<<"$content") bytes, dry-run"
        log_debug "dry-run write: $path"
        return 0
    fi
    log_journal "$category" write "$path" "$(wc -c <<<"$content") bytes"
    printf "%s" "$content" > "$path"
}
