#!/usr/bin/env bash
#
# SYNOPSIS
#     Диспетчер бутстрапа: семейство из каталога вызывает свой бэкенд.
#
# DESCRIPTION
#     Бэкенды не знают ни о разметке, ни о сети: их контракт один -
#     населить корень целевой системы базовыми пакетами. Всё исполнение
#     идёт через run_exec, поэтому dry-run journallит точные команды.

# shellcheck source=lib/bootstrap/debootstrap.sh
source "${LRI_ROOT:-.}/lib/bootstrap/debootstrap.sh"
# shellcheck source=lib/bootstrap/dnf.sh
source "${LRI_ROOT:-.}/lib/bootstrap/dnf.sh"
# shellcheck source=lib/bootstrap/zypper.sh
source "${LRI_ROOT:-.}/lib/bootstrap/zypper.sh"
# shellcheck source=lib/bootstrap/pacstrap.sh
source "${LRI_ROOT:-.}/lib/bootstrap/pacstrap.sh"
# shellcheck source=lib/bootstrap/apk.sh
source "${LRI_ROOT:-.}/lib/bootstrap/apk.sh"
# shellcheck source=lib/bootstrap/proxmox.sh
source "${LRI_ROOT:-.}/lib/bootstrap/proxmox.sh"

bootstrap_run() {
    local family="$1" target="$2" mode="${3:-bios}"
    case "$family" in
        debootstrap) bootstrap_debootstrap "$target" "$mode" ;;
        dnf)         bootstrap_dnf "$target" "$mode" ;;
        zypper)      bootstrap_zypper "$target" "$mode" ;;
        pacstrap)    bootstrap_pacstrap "$target" "$mode" ;;
        apk)         bootstrap_apk "$target" "$mode" ;;
        proxmox)     bootstrap_proxmox "$target" "$mode" ;;
        *)
            log_error "No bootstrap backend for family: $family"
            return 1
            ;;
    esac
}
