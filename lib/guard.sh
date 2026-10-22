#!/usr/bin/env bash
#
# SYNOPSIS
#     Защитные проверки перед любыми побочными эффектами.
#
# DESCRIPTION
#     Стирание диска необратимо, поэтому проверки отделены от действий и
#     тестируются отдельно. Таблица монтирования читается из переменной
#     LRI_MOUNTS_FILE (по умолчанию /proc/mounts), чтобы тесты могли
#     подсунуть фикстуру без привилегий.

guard_root() {
    if (( LRI_DRY_RUN )); then
        return 0
    fi
    if (( EUID != 0 )); then
        log_error "This tool needs root; re-run via sudo or as root."
        return 2
    fi
    return 0
}

# Диск, на котором стоит работающая система, стирать нельзя: в rescue корень
# обычно tmpfs, а на live-образах целевой диск не смонтирован как / .
guard_disk_free() {
    local disk="$1" mounts="${LRI_MOUNTS_FILE:-/proc/mounts}" dev rest
    while read -r dev _ rest; do
        if [[ "$dev" == "$disk"* ]]; then
            log_error "Refusing: $disk (or a partition of it) is mounted at ${rest%% *}"
            return 2
        fi
    done < "$mounts"
    if [[ ! -b "$disk" && ! -f "$disk" ]]; then
        if (( LRI_DRY_RUN )); then
            log_warn "Disk $disk does not exist; dry-run continues with a journal note."
            log_journal guard disk-missing "$disk" "dry-run"
            return 0
        fi
        log_error "Target is not a block device or image file: $disk"
        return 2
    fi
    return 0
}

# Подтверждение оператора: стирание диска требует явного да, если не передан
# --yes. Отказ это не ошибка прогона: код 0 и сообщение в логе.
guard_confirm() {
    local summary="$1" answer
    if (( LRI_YES )); then
        return 0
    fi
    if (( LRI_DRY_RUN )); then
        return 0
    fi
    printf "%s\n" "$summary"
    printf "Type yes to wipe the target disk: "
    read -r answer || answer=""
    if [[ "$answer" != "yes" ]]; then
        log_warn "Operator declined; nothing was changed."
        return 3
    fi
    return 0
}

# Эвристика rescue-окружения: корень на tmpfs или наличие маркеров провайдера.
# Не ошибка: предупреждение, потому что запуск с live-ISO тоже легитимен.
guard_rescue_hint() {
    local mounts="${LRI_MOUNTS_FILE:-/proc/mounts}" rootfs
    rootfs="$(awk '$2 == "/" {print $1}' "$mounts" 2>/dev/null || true)"
    if [[ "$rootfs" == *tmpfs* || -d /rescue || -f /etc/rescue-mode ]]; then
        log_debug "Rescue-like environment detected."
        return 0
    fi
    log_warn "Not a rescue environment (root on $rootfs): continuing will replace the running system."
    return 0
}
