#!/usr/bin/env bash
# Alpine: alpine-base плюс openssh и ядро; fstab и загрузчик наши.
bootstrap_apk() {
    local target="$1"
    run_exec bootstrap apk --arch x86_64 --root "$target" --no-initdb \
        --repository "$LRI_CAT_MIRROR/v$LRI_CAT_RELEASE/main" \
        add alpine-base openssh "$LRI_CAT_KERNEL" grub-bios grub-efi efibootmgr
}
