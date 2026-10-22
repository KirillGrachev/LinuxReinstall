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
            printf 'The distro catalog lands in the next commit.\n'
            ;;
        run)
            printf 'Parsed: distro=%s disk=%s dry_run=%s\n' \
                "$LRI_DISTRO" "$LRI_DISK" "$LRI_DRY_RUN"
            ;;
    esac
}

main "$@"
