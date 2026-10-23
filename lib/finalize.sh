#!/usr/bin/env bash
#
# SYNOPSIS
#     Chroot-финализация целевой системы после бутстрапа.
#
# DESCRIPTION
#     fstab по UUID, hostname, часовой пояс и локаль, sshd с ключом оператора
#     и загрузчик. Всё через run_exec/run_write_file, поэтому dry-run
#     journallит каждый шаг, не трогая целевую систему.

# Чистый рендер fstab: тесты гоняют вывод через структурные проверки
# без устройств и uuid из blkid.
finalize_render_fstab() {
    local root_uuid="$1" esp_uuid="$2" swap_uuid="$3" mode="$4" swap_n="$5"
    local content="UUID=$root_uuid / ext4 defaults 0 1
"
    if [[ "$mode" == "efi" ]]; then
        content+="UUID=$esp_uuid /boot/efi vfat umask=0077 0 2
"
    fi
    if [[ "$swap_n" != "-" ]]; then
        content+="UUID=$swap_uuid none swap sw 0 0
"
    fi
    printf "%s" "$content"
}

finalize_fstab() {
    local target="$1" disk="$2" mode="$3" swap_mb="$4"
    local nums boot_n swap_n root_n root_uuid esp_uuid swap_uuid
    nums="$(disk_part_numbers "$swap_mb")"
    read -r boot_n swap_n root_n <<< "$nums"
    if (( LRI_DRY_RUN )); then
        root_uuid=DRYRUN-ROOT; esp_uuid=DRYRUN-ESP; swap_uuid=DRYRUN-SWAP
    else
        root_uuid="$(blkid -s UUID -o value "$(disk_part_name "$disk" "$root_n")")"
        esp_uuid="$(blkid -s UUID -o value "$(disk_part_name "$disk" "$boot_n")")"
        swap_uuid="$(blkid -s UUID -o value "$(disk_part_name "$disk" "$swap_n")")"
    fi
    run_write_file finalize "$target/etc/fstab" \
        "$(finalize_render_fstab "$root_uuid" "$esp_uuid" "$swap_uuid" "$mode" "$swap_n")"
}

finalize_hostname() {
    local target="$1" name="$2"
    run_write_file finalize "$target/etc/hostname" "$name
"
    run_write_file finalize "$target/etc/hosts" "127.0.0.1 localhost
127.0.1.1 $name
"
}

finalize_locale_tz() {
    local target="$1" family="$2" tz="$3"
    # systemd-firstboot молча возвращает 1 в части chroot-окружений, поэтому
    # локаль и часовой пояс ставятся детерминированно: файл и симлинк.
    if [[ "$family" == "apk" ]]; then
        run_write_file finalize "$target/etc/timezone" "$tz
"
    else
        run_write_file finalize "$target/etc/locale.conf" "LANG=C.UTF-8
"
    fi
    run_exec finalize chroot "$target" ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
}

finalize_sshd() {
    local target="$1" key="$2"
    run_exec finalize mkdir -p "$target/root/.ssh"
    run_write_file finalize "$target/root/.ssh/authorized_keys" "$key
"
    run_exec finalize chmod 700 "$target/root/.ssh"
    run_exec finalize chmod 600 "$target/root/.ssh/authorized_keys"
    # Arch and openSUSE ship an sshd_config without an Include for the
    # drop-in directory: prepend one, otherwise the hardening is dead text.
    run_exec finalize chroot "$target" sh -c \
        "grep -q 'Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config"
    run_write_file finalize "$target/etc/ssh/sshd_config.d/00-LinuxReinstall.conf" \
        "PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
"
}

# busybox init не поднимает getty на serial сам: добавляем строку в inittab,
# иначе консоль ttyS0, обещанная cmdline, останется без логина.
finalize_serial_getty() {
    local target="$1" family="$2"
    [[ "$family" == "apk" ]] || return 0
    run_exec finalize chroot "$target" sh -c \
        "grep -q '^ttyS0::' /etc/inittab || printf 'ttyS0::/sbin/getty -L 115200 ttyS0 vt100\n' >> /etc/inittab"
}

finalize_bootloader() {
    local target="$1" disk="$2" mode="$3" family="$4"
    local grub grubmk conf
    case "$family" in
        dnf|zypper) grub="grub2-install"; grubmk="grub2-mkconfig"; conf="/boot/grub2/grub.cfg" ;;
        *)          grub="grub-install";  grubmk="grub-mkconfig";  conf="/boot/grub/grub.cfg" ;;
    esac
    if [[ "$mode" == "efi" ]]; then
        run_exec finalize chroot "$target" "$grub" --target=x86_64-efi \
            --efi-directory=/boot/efi --bootloader-id=LinuxReinstall
        # Fallback path for machines whose NVRAM does not keep the entry:
        # fresh boards, reset firmware, images moved between hosts.
        run_exec finalize chroot "$target" "$grub" --target=x86_64-efi \
            --efi-directory=/boot/efi --bootloader-id=LinuxReinstall --removable
    else
        run_exec finalize chroot "$target" "$grub" --target=i386-pc "$disk"
    fi
    # Serial console in the kernel cmdline: headless machines and every
    # boot verification (qemu -serial stdio) need a console to talk to.
    run_exec finalize chroot "$target" sh -c \
        "grep -q console=ttyS0 /etc/default/grub 2>/dev/null || printf 'GRUB_CMDLINE_LINUX=\"console=ttyS0,115200\"\n' >> /etc/default/grub"
    run_exec finalize chroot "$target" "$grubmk" -o "$conf"
}
