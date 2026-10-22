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

# Фикстуры отказов: тестам нужно проверять пути ошибок пайплайна, а сухому
# прогону иначе неоткуда взять ненулевой код. Фикстуры приходят файлом
# (TSV: шаблон<TAB>код) через LRI_FIXTURE_FILE, потому что ассоциативные
# массивы не экспортируются, а точка входа сама сорсит эту библиотеку.
# Шаблон сопоставляется с той же строкой, что уходит в журнал.
declare -gA LRI_FIXTURES=()

if [[ -n "${LRI_FIXTURE_FILE:-}" && -r "${LRI_FIXTURE_FILE:-}" ]]; then
    while IFS=$'\t' read -r LRI_FIX_PATTERN LRI_FIX_RC; do
        [[ -n "$LRI_FIX_PATTERN" ]] && LRI_FIXTURES["$LRI_FIX_PATTERN"]="$LRI_FIX_RC"
    done < "$LRI_FIXTURE_FILE"
fi

run_fixture_rc() {
    local pretty="$1" pattern
    for pattern in "${!LRI_FIXTURES[@]}"; do
        # shellcheck disable=SC2053  # намеренное сопоставление с шаблоном
        if [[ "$pretty" == $pattern ]]; then
            printf "%s" "${LRI_FIXTURES[$pattern]}"
            return 0
        fi
    done
    return 1
}

run_exec() {
    local category="$1"; shift
    local pretty="$*"
    local frc=""
    frc="$(run_fixture_rc "$pretty")" || frc=""
    if (( LRI_DRY_RUN )); then
        log_journal "$category" exec "$pretty" "dry-run rc=${frc:-0}"
        log_debug "dry-run: $pretty"
        [[ -n "$frc" ]] && return "$frc"
        return 0
    fi
    log_journal "$category" exec "$pretty" "real"
    log_info "exec: $pretty"
    "$@"
}

run_write_file() {
    local category="$1" path="$2" content="$3"
    local frc=""
    frc="$(run_fixture_rc "write $path")" || frc=""
    if (( LRI_DRY_RUN )); then
        log_journal "$category" write "$path" "$(wc -c <<<"$content") bytes, dry-run rc=${frc:-0}"
        log_debug "dry-run write: $path"
        [[ -n "$frc" ]] && return "$frc"
        return 0
    fi
    log_journal "$category" write "$path" "$(wc -c <<<"$content") bytes"
    printf "%s" "$content" > "$path"
}

# Команда, читающая stdin из файла: в dry-run исполнять нечего, но точная
# командная строка обязана попасть в журнал, иначе план непроверяем.
run_exec_stdin() {
    local category="$1" stdin_file="$2"; shift 2
    local pretty="$* < $stdin_file"
    local frc=""
    frc="$(run_fixture_rc "$pretty")" || frc=""
    if (( LRI_DRY_RUN )); then
        log_journal "$category" exec "$pretty" "dry-run rc=${frc:-0}"
        log_debug "dry-run: $pretty"
        [[ -n "$frc" ]] && return "$frc"
        return 0
    fi
    log_journal "$category" exec "$pretty" "real"
    log_info "exec: $pretty"
    "$@" < "$stdin_file"
}
