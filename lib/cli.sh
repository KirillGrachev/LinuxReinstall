#!/usr/bin/env bash
#
# SYNOPSIS
#     Разбор аргументов командной строки reinstall.sh.
#
# DESCRIPTION
#     Только разбор и валидация: никаких побочных эффектов, кроме чтения
#     файла ключа, поэтому контракт кодов возврата (0/2) тестируется без
#     обращения к диску. Значения раскладываются в глобальные LRI_*,
#     единственное место с именами опций и дефолтами.

# Глобалки этого файла читаются другими модулями после source,
# поэтому SC2034 здесь не дефект, а контракт.
# shellcheck disable=SC2034
LRI_VERSION="0.1.0"

cli_usage() {
    cat <<'USAGE'
Usage: reinstall.sh --distro NAME --disk DEV [options]

Reinstall a bare machine from a rescue or live environment: wipe the target
disk, bootstrap the chosen distro family into it and finalize network,
bootloader and sshd access.

Required:
  --distro NAME         Distro slug from the catalog (see --list-distros)
  --disk DEV            Target block device, e.g. /dev/sda (contents destroyed)

Options:
  --hostname NAME       Target hostname (default: current rescue hostname)
  --ssh-key KEY         Public key line for root authorized_keys
  --ssh-key-file PATH   Read the public key from a file instead
  --network dhcp|static Addressing of the target (default: dhcp)
  --address CIDR        Static address, required with --network static
  --gateway ADDR        Static gateway
  --dns ADDR            DNS server, repeatable (default: carried from rescue)
  --boot auto|efi|bios  Partitioning/boot mode (default: auto, probe firmware)
  --swap MB             Swap partition size in MiB (default: 0, no swap)
  --timezone TZ         Target timezone (default: UTC)
  --log PATH            Log file path (default: /tmp/reinstall-<stamp>.log)
  --list-distros        Print the catalog and exit
  --dry-run             Journal every planned action, change nothing
  --yes, -y             Skip the interactive confirmation
  --verbose, -v         Debug log level
  --help, -h            This help
  --version             Print version and exit

Exit codes:
  0   success, or help/version requested
  1   runtime failure
  2   usage or guard error
USAGE
}

# Берёт значение опции или отклоняет запуск: опция без значения это ошибка
# использования, а не тихая пустота в нужном поле.
cli_take_value() {
    if (( $# < 2 )) || [[ "${2:-}" == --* ]]; then
        printf 'Option %s requires a value\n' "$1" >&2
        return 2
    fi
    printf '%s' "$2"
}

cli_parse() {
    LRI_DISTRO="" LRI_DISK="" LRI_HOSTNAME="" LRI_SSH_KEY="" LRI_SSH_KEY_FILE=""
    LRI_NETWORK="dhcp" LRI_ADDRESS="" LRI_GATEWAY="" LRI_DNS=() LRI_BOOT="auto"
    LRI_SWAP_MB=0 LRI_TIMEZONE="UTC" LRI_LOG="" LRI_DRY_RUN=0 LRI_YES=0
    LRI_VERBOSE=0 LRI_ACTION="run"
    local value
    while (( $# > 0 )); do
        case "$1" in
            --distro|--disk|--hostname|--ssh-key|--ssh-key-file|--network|\
            --address|--gateway|--dns|--boot|--swap|--timezone|--log)
                value="$(cli_take_value "$@")" || return 2
                case "$1" in
                    --distro)       LRI_DISTRO="$value" ;;
                    --disk)         LRI_DISK="$value" ;;
                    --hostname)     LRI_HOSTNAME="$value" ;;
                    --ssh-key)      LRI_SSH_KEY="$value" ;;
                    --ssh-key-file) LRI_SSH_KEY_FILE="$value" ;;
                    --network)      LRI_NETWORK="$value" ;;
                    --address)      LRI_ADDRESS="$value" ;;
                    --gateway)      LRI_GATEWAY="$value" ;;
                    --dns)          LRI_DNS+=("$value") ;;
                    --boot)         LRI_BOOT="$value" ;;
                    --swap)         LRI_SWAP_MB="$value" ;;
                    --timezone)     LRI_TIMEZONE="$value" ;;
                    --log)          LRI_LOG="$value" ;;
                esac
                shift 2
                ;;
            --list-distros) LRI_ACTION="list"; shift ;;
            --dry-run)      LRI_DRY_RUN=1; shift ;;
            --yes|-y)       LRI_YES=1; shift ;;
            --verbose|-v)   LRI_VERBOSE=1; shift ;;
            --help|-h)      LRI_ACTION="help"; shift ;;
            --version)      LRI_ACTION="version"; shift ;;
            *)
                printf 'Unknown argument: %s\n' "$1" >&2
                printf 'Run with --help to see the argument list.\n' >&2
                return 2
                ;;
        esac
    done
    return 0
}

cli_validate() {
    case "$LRI_ACTION" in
        help|version|list) return 0 ;;
    esac
    if [[ -z "$LRI_DISTRO" ]]; then
        printf 'Missing required argument: --distro\n' >&2
        return 2
    fi
    if [[ -z "$LRI_DISK" ]]; then
        printf 'Missing required argument: --disk\n' >&2
        return 2
    fi
    if [[ -n "$LRI_SSH_KEY" && -n "$LRI_SSH_KEY_FILE" ]]; then
        printf 'Use either --ssh-key or --ssh-key-file, not both\n' >&2
        return 2
    fi
    if [[ -n "$LRI_SSH_KEY_FILE" && ! -f "$LRI_SSH_KEY_FILE" ]]; then
        printf 'Key file not found: %s\n' "$LRI_SSH_KEY_FILE" >&2
        return 2
    fi
    case "$LRI_NETWORK" in
        dhcp|static) ;;
        *) printf 'Invalid --network value: %s (expected dhcp or static)\n' "$LRI_NETWORK" >&2; return 2 ;;
    esac
    if [[ "$LRI_NETWORK" == "static" && -z "$LRI_ADDRESS" ]]; then
        printf 'Static network requires --address CIDR\n' >&2
        return 2
    fi
    case "$LRI_BOOT" in
        auto|efi|bios) ;;
        *) printf 'Invalid --boot value: %s (expected auto, efi or bios)\n' "$LRI_BOOT" >&2; return 2 ;;
    esac
    if (( ! LRI_DRY_RUN )) && [[ -z "$LRI_SSH_KEY" && -z "$LRI_SSH_KEY_FILE" ]]; then
        printf 'A real run needs an SSH key: pass --ssh-key or --ssh-key-file\n' >&2
        return 2
    fi
    if ! [[ "$LRI_SWAP_MB" =~ ^[0-9]+$ ]]; then
        printf 'Invalid --swap value: %s (expected MiB as a number)\n' "$LRI_SWAP_MB" >&2
        return 2
    fi
    return 0
}
