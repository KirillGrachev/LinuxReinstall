#!/usr/bin/env bash
# Proxmox VE это Debian с репозиторием PVE: бутстрапим bookworm и кладём
# список репозиториев до финализации, пакеты PVE ставятся уже в цели.
bootstrap_proxmox() {
    local target="$1"
    bootstrap_debootstrap "$target" "${2:-bios}" || return 1
    run_write_file bootstrap "$target/etc/apt/sources.list.d/pve.list" \
        "deb http://download.proxmox.com/debian/pve $LRI_CAT_RELEASE pve-no-subscription
"
}
