#!/usr/bin/env bash
# openSUSE: сначала репозиторий в корне, затем установка base-набора.
bootstrap_zypper() {
    local target="$1"
    run_exec bootstrap zypper --non-interactive --root "$target" \
        addrepo --refresh "$LRI_CAT_MIRROR/repo/oss/main" main || return 1
    run_exec bootstrap zypper --non-interactive --root "$target" \
        install --auto-agree-with-licenses systemd openssh grub2 x86-efi
}
