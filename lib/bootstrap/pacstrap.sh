#!/usr/bin/env bash
# Arch: pacstrap с ключами и без генерации fstab (fstab пишем сами).
bootstrap_pacstrap() {
    local target="$1"
    run_exec bootstrap pacstrap -K -G -M "$target" base "$LRI_CAT_KERNEL" openssh grub
}
