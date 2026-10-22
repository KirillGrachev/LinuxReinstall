#!/usr/bin/env bash
#
# SYNOPSIS
#     Журнал в файл плюс консоль, и TSV-журнал операций для dry-run.
#
# DESCRIPTION
#     Два независимых потока: человекочитаемый лог (уровни, метки времени)
#     и журнал операций (категория, операция, цель, детали), который в
#     dry-run заменяет собой побочные эффекты: модули пишут в него то, что
#     они сделали бы по-настоящему.

LRI_LOG_FILE=""
LRI_LOG_VERBOSE=0
LRI_JOURNAL_FILE=""

log_init() {
    LRI_LOG_FILE="$1"
    LRI_LOG_VERBOSE="${2:-0}"
    : > "$LRI_LOG_FILE"
}

log_journal_init() {
    LRI_JOURNAL_FILE="$1"
    : > "$LRI_JOURNAL_FILE"
}

_log_write() {
    local level="$1"; shift
    local line
    line="$(date "+%Y-%m-%d %H:%M:%S") [$level] $*"
    if [[ -n "$LRI_LOG_FILE" ]]; then
        printf "%s\n" "$line" >> "$LRI_LOG_FILE"
    fi
    case "$level" in
        DEBUG)
            (( LRI_LOG_VERBOSE )) || return 0
            printf "[DEBUG] %s\n" "$*"
            ;;
        WARN)  printf "[WARN] %s\n" "$*" ;;
        ERROR) printf "[ERROR] %s\n" "$*" >&2 ;;
        *)     printf "[INFO] %s\n" "$*" ;;
    esac
}

log_info()  { _log_write INFO  "$@"; }
log_warn()  { _log_write WARN  "$@"; }
log_error() { _log_write ERROR "$@"; }
log_debug() { _log_write DEBUG "$@"; }

# Строка журнала операций: TSV, как в остальных проектах автора, чтобы
# прогон разбирался grep-ом без парсера.
log_journal() {
    local category="$1" operation="$2" target="$3" details="${4:-}"
    [[ -n "$LRI_JOURNAL_FILE" ]] || return 0
    printf "%s\t%s\t%s\t%s\n" "$category" "$operation" "$target" "$details" >> "$LRI_JOURNAL_FILE"
}
