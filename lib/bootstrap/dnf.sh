#!/usr/bin/env bash
# RPM-линейка через dnf --installroot: группа core плюс sshd и grub2 обеих
# прошивок, потому что режим boot мог быть определён как auto поздновато.
bootstrap_dnf() {
    local target="$1"
    run_exec bootstrap dnf -y --installroot="$target" \
        --releasever="$LRI_CAT_RELEASE" --setopt=install_weak_deps=False \
        install @core openssh-server grub2 grub2-efi-x64 shim-x64 efi-filesystem efibootmgr "$LRI_CAT_KERNEL"
}
