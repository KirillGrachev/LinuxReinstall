#!/usr/bin/env bash
#
# SYNOPSIS
#     Разметка целевого диска: GPT для EFI и BIOS, опциональный swap.
#
# DESCRIPTION
#     Раскладка намеренно простая и одинаковая для всех семейств:
#       EFI : p1 ESP 512 MiB, p2 swap (опционально), p3 root ext4
#       BIOS: p1 bios_grub 1 MiB, p2 swap (опционально), p3 root ext4
#     sfdisk-скрипт рендерится отдельной чистой функцией: её вывод тестируется
#     без всяких устройств, а применение идёт через run_exec/run_exec_stdin.

disk_detect_boot() {
    if [[ "$LRI_BOOT" != "auto" ]]; then
        printf "%s" "$LRI_BOOT"
        return 0
    fi
    if [[ -d /sys/firmware/efi ]]; then
        printf "efi"
    else
        printf "bios"
    fi
}

# Имя раздела: nvme и mmc добавляют p, классические диски - нет.
disk_part_name() {
    local disk="$1" num="$2"
    if [[ "$disk" =~ [0-9]$ ]]; then
        printf "%sp%s" "$disk" "$num"
    else
        printf "%s%s" "$disk" "$num"
    fi
}

disk_render_sfdisk() {
    local mode="$1" swap_mb="${2:-0}"
    printf "label: gpt\n"
    if [[ "$mode" == "efi" ]]; then
        printf "size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp\n"
    else
        printf "size=1MiB, type=21686148-6449-6E6F-744E-656564454649, name=biosboot\n"
    fi
    if (( swap_mb > 0 )); then
        printf "size=%sMiB, type=0657FD6D-A4AB-44C4-84E5-0933C84B4F4F, name=swap\n" "$swap_mb"
    fi
    printf "type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root\n"
}

# Номера разделов: boot swap root; swap=0 даёт пустое поле swap.
disk_part_numbers() {
    local swap_mb="${1:-0}"
    if (( swap_mb > 0 )); then
        printf "1 2 3"
    else
        printf "1 - 2"
    fi
}

disk_apply() {
    local disk="$1" mode="$2" swap_mb="$3" script="$4"
    local nums boot_n swap_n root_n
    nums="$(disk_part_numbers "$swap_mb")"
    read -r boot_n swap_n root_n <<< "$nums"
    run_exec disk wipefs -a "$disk" || return 1
    run_write_file disk "$script" "$(disk_render_sfdisk "$mode" "$swap_mb")"
    run_exec_stdin disk "$script" sfdisk --force "$disk" || return 1
    # На loop-устройствах и занятых дисках ядро может отложить перечитывание
    # таблицы: partx заставляет его увидеть разделы до mkfs.
    run_exec disk partx --update "$disk" || return 1
    disk_ensure_part_nodes "$disk" "$boot_n" "$swap_n" "$root_n"
    if [[ "$mode" == "efi" ]]; then
        run_exec disk mkfs.vfat -F32 "$(disk_part_name "$disk" "$boot_n")" || return 1
    fi
    if [[ "$swap_n" != "-" ]]; then
        run_exec disk mkswap "$(disk_part_name "$disk" "$swap_n")" || return 1
    fi
    run_exec disk mkfs.ext4 -F "$(disk_part_name "$disk" "$root_n")" || return 1
}

# Без udev (контейнеры, минимальные rescue) ядро знает о разделах, но узлы
# в /dev никто не создаёт: дочитываем major:minor из sysfs и mknod-им.
# На системах с udev узлы уже есть и функция ничего не делает.
disk_ensure_part_nodes() {
    local disk="$1"; shift
    local num name base sys devno maj min
    for num in "$@"; do
        [[ -n "$num" && "$num" != "-" ]] || continue
        name="$(disk_part_name "$disk" "$num")"
        [[ -e "$name" ]] && continue
        base="${name##*/}"
        sys="/sys/class/block/$base/dev"
        if [[ ! -r "$sys" ]]; then
            log_warn "Partition node $name is missing and sysfs has no entry; skipping."
            continue
        fi
        devno="$(cat "$sys")"
        maj="${devno%%:*}"
        min="${devno##*:}"
        run_exec disk mknod -b "$name" "$maj" "$min"
    done
}

disk_mount_target() {
    local disk="$1" mode="$2" swap_mb="$3" target="$4"
    local nums boot_n swap_n root_n
    nums="$(disk_part_numbers "$swap_mb")"
    read -r boot_n swap_n root_n <<< "$nums"
    run_exec disk mkdir -p "$target"
    run_exec disk mount "$(disk_part_name "$disk" "$root_n")" "$target" || return 1
    if [[ "$mode" == "efi" ]]; then
        run_exec disk mkdir -p "$target/boot/efi"
        run_exec disk mount "$(disk_part_name "$disk" "$boot_n")" "$target/boot/efi" || return 1
    fi
    # chroot-финализации (grub-install, systemd-firstboot) нужны устройства
    # и виртуальные ФС цели: без bind-mount grub не увидит диск.
    run_exec disk mount --bind /dev "$target/dev" || return 1
    run_exec disk mount --bind /proc "$target/proc" || return 1
    run_exec disk mount --bind /sys "$target/sys" || return 1
}
