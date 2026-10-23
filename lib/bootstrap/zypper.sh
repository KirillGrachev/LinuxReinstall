#!/usr/bin/env bash
# openSUSE: сначала репозиторий в корне, затем установка base-набора.
bootstrap_zypper() {
    local target="$1"
    run_exec bootstrap rpm --root "$target" --initdb
    # The repodata signing key can be expired while the host trusts a
    # rotated key from its own db: seed the installroot with the host
    # keyring so refresh verifies exactly like on the host.
    run_exec bootstrap sh -c "rpm --root '$target' --import /etc/pki/rpm-gpg/* 2>/dev/null || true"
    run_exec bootstrap zypper --non-interactive --gpg-auto-import-keys --root "$target" \
        addrepo --refresh "$LRI_CAT_MIRROR" main || return 1
    run_exec bootstrap zypper --non-interactive --gpg-auto-import-keys --root "$target" \
        install --auto-agree-with-licenses systemd openssh grub2 grub2-x86_64-efi shim efibootmgr "$LRI_CAT_KERNEL"
}
