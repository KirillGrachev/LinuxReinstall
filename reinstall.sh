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
            printf 'Resolved: %s (%s, %s) on %s; pipeline lands in the next commits\n' \
                "$LRI_CAT_SLUG" "$LRI_CAT_FAMILY" "$LRI_CAT_RELEASE" "$LRI_DISK"
            ;;
    esac
}

main "$@"
