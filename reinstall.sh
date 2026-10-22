#!/usr/bin/env bash
#
# SYNOPSIS
#     Точка входа: разбор аргументов и диспетчеризация действий.
#
# DESCRIPTION
#     Тонкая точка входа по образцу остальных проектов автора: весь смысл
#     живёт в lib/*, здесь только разбор, коды возврата и выбор действия.
#     Коды: 0 успех (или справка), 1 runtime-ошибка, 2 ошибка использования
#     или защитных проверок.
set -euo pipefail

LRI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cli.sh
source "$LRI_ROOT/lib/cli.sh"
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/catalog.sh
source "$LRI_ROOT/lib/catalog.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/guard.sh
source "$LRI_ROOT/lib/guard.sh"
# shellcheck source=lib/disk.sh
source "$LRI_ROOT/lib/disk.sh"
# shellcheck source=lib/net.sh
source "$LRI_ROOT/lib/net.sh"
# shellcheck source=lib/bootstrap.sh
source "$LRI_ROOT/lib/bootstrap.sh"
# shellcheck source=lib/finalize.sh
source "$LRI_ROOT/lib/finalize.sh"

# Пайплайн переустановки: защиты, разметка, бутстрап, сеть, финализация.
# Каждый этап journallится; падение этапа останавливает прогон с кодом 1.
pipeline_run() {
    local target=/mnt/lri-target mode key
    guard_root || exit 2
    guard_rescue_hint
    guard_disk_free "$LRI_DISK" || exit 2
    if (( ! LRI_DRY_RUN )) && [[ -z "$LRI_SSH_KEY" && -z "$LRI_SSH_KEY_FILE" ]]; then
        log_error "Refusing a real run without an SSH key: pass --ssh-key or --ssh-key-file, or use --dry-run."
        exit 2
    fi
    key="$LRI_SSH_KEY"
    if [[ -n "$LRI_SSH_KEY_FILE" ]]; then
        key="$(cat "$LRI_SSH_KEY_FILE")"
    fi
    guard_family_tools "$LRI_CAT_FAMILY" || exit 2
    mode="$(disk_detect_boot)"
    net_capture
    guard_confirm "Will wipe $LRI_DISK and install $LRI_CAT_SLUG ($LRI_CAT_FAMILY, $mode)." || {
        local rc=$?
        if (( rc == 3 )); then exit 0; fi
        exit 2
    }
    disk_apply "$LRI_DISK" "$mode" "$LRI_SWAP_MB" /tmp/lri-sfdisk.txt || exit 1
    disk_mount_target "$LRI_DISK" "$mode" "$LRI_SWAP_MB" "$target" || exit 1
    bootstrap_run "$LRI_CAT_FAMILY" "$target" "$mode" || exit 1
    disk_bind_for_chroot "$target" || exit 1
    net_apply "$target" "$LRI_CAT_FAMILY" || exit 1
    finalize_fstab "$target" "$LRI_DISK" "$mode" "$LRI_SWAP_MB" || exit 1
    finalize_hostname "$target" "${LRI_HOSTNAME:-$(hostname)}" || exit 1
    finalize_locale_tz "$target" "$LRI_CAT_FAMILY" "$LRI_TIMEZONE" || exit 1
    finalize_sshd "$target" "$key" || exit 1
    finalize_bootloader "$target" "$LRI_DISK" "$mode" "$LRI_CAT_FAMILY" || exit 1
    run_exec disk umount -R "$target" || exit 1
    log_info "Reinstall staged; reboot the machine to boot the new system."
    printf 'Journal: %s\n' "$LRI_JOURNAL_FILE"
}

main() {
    cli_parse "$@" || exit 2
    cli_validate || exit 2
    case "$LRI_ACTION" in
        help)
            cli_usage
            ;;
        version)
            printf 'reinstall %s\n' "$LRI_VERSION"
            ;;
        list)
            catalog_list
            ;;
        run)
            if ! catalog_resolve "$LRI_DISTRO"; then
                printf 'Unknown distro: %s\n' "$LRI_DISTRO" >&2
                printf 'Available slugs:\n' >&2
                catalog_list >&2
                exit 2
            fi
            : "${LRI_LOG:=/tmp/reinstall-$(date +%Y%m%d-%H%M%S).log}"
            log_init "$LRI_LOG" "$LRI_VERBOSE"
            log_journal_init "/tmp/reinstall-journal.tsv"
            log_info "Target: distro=$LRI_CAT_SLUG family=$LRI_CAT_FAMILY disk=$LRI_DISK dry_run=$LRI_DRY_RUN"
            pipeline_run
            ;;
    esac
}

main "$@"
