#!/usr/bin/env bash
# Alpine: alpine-base плюс openssh и ядро; fstab и загрузчик наши.
bootstrap_apk() {
    local target="$1"
    # A fresh root has no apk keys: without them the repository index is
    # UNTRUSTED and package selection fails. Seed them from the host.
    run_exec bootstrap sh -c "mkdir -p '$target/etc/apk/keys' && cp /etc/apk/keys/*.pub '$target/etc/apk/keys/' 2>/dev/null || true"
    run_exec bootstrap apk --arch x86_64 --root "$target" --initdb \
        --repository "$LRI_CAT_MIRROR/v$LRI_CAT_RELEASE/main" \
        add alpine-base openssh "$LRI_CAT_KERNEL" grub-bios grub-efi efibootmgr
}
