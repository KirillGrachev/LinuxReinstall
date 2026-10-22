#!/usr/bin/env bash
# Бутстрап дебиан-линейки: base-система плюс sshd и grub, чтобы финализация
# смогла поставить загрузчик и дать доступ по ключу.
bootstrap_debootstrap() {
    local target="$1" mode="${2:-bios}"
    local grub=grub2
    [[ "$mode" == "efi" ]] && grub="grub-efi-amd64"
    run_exec bootstrap debootstrap --arch=amd64 \
        --include=openssh-server,$grub,systemd-sysv,ifupdown,"$LRI_CAT_KERNEL" \
        "$LRI_CAT_RELEASE" "$target" "$LRI_CAT_MIRROR"
}
