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
    disk_wait_partitions "$disk" "$boot_n" "$swap_n" "$root_n"
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
    local num name base sys devno maj min cur_maj cur_min line
    for num in "$@"; do
        [[ -n "$num" && "$num" != "-" ]] || continue
        name="$(disk_part_name "$disk" "$num")"
        base="${name##*/}"
        # partx читает таблицу ядра ioctl-ом и синхронен; sysfs наполняется
        # асинхронно, поэтому берём major:minor из partx, а sysfs лишь запас.
        line="$(partx --raw --print "$disk" 2>/dev/null | awk -v b="$base" '$4 == b {print $1, $2; exit}')"
        if [[ -z "$line" ]]; then
            sys="/sys/class/block/$base/dev"
            if [[ -r "$sys" ]]; then
                devno="$(cat "$sys")"
                line="${devno%%:*} ${devno##*:}"
            fi
        fi
        if [[ -z "$line" ]]; then
            log_warn "Partition node $name is missing and no source reports it; skipping."
            continue
        fi
        read -r maj min <<< "$line"
        if [[ -e "$name" ]]; then
            # Узел мог остаться от прошлой разметки с другими номерами:
            # сверяем major:minor и пересоздаём при расхождении.
            cur_maj="$(( 0x$(stat -c %t "$name") ))"
            cur_min="$(( 0x$(stat -c %T "$name") ))"
            if (( cur_maj == maj && cur_min == min )); then
                continue
            fi
            log_warn "Stale node $name ($cur_maj:$cur_min, expected $maj:$min); recreating."
            run_exec disk rm -f "$name" || return 1
        fi
        run_exec disk mknod "$name" b "$maj" "$min" || return 1
    done
}

# Перечитывание таблицы разделов на loop-устройствах асинхронно: сразу
# после sfdisk ядро может видеть лишь часть разделов. Ждём, пока partx
# покажет все ожидаемые, иначе mkfs получит отсутствующие узлы.
disk_wait_partitions() {
    local disk="$1"; shift
    (( LRI_DRY_RUN )) && return 0
    local expected=0 num have attempt
    for num in "$@"; do
        [[ -n "$num" && "$num" != "-" ]] && expected=$(( expected + 1 ))
    done
    local attempt=0
    while (( attempt < 15 )); do
        have="$(partx --raw --print "$disk" 2>/dev/null | wc -l)"
        (( have >= expected )) && return 0
        attempt=$(( attempt + 1 ))
        sleep 0.4
    done
    log_warn "Partition table on $disk reports $have of $expected after waiting; continuing anyway."
    return 0
}

# Без udev (контейнеры, минимальные rescue) нет ссылок /dev/disk/by-uuid,
# и grub-probe падает в root=/dev/... вместо root=UUID=..., что ломает
# загрузку при смене имени диска. Создаём ссылки сами по данным blkid.
disk_ensure_uuid_links() {
    local disk="$1"; shift
    local num node uuid
    for num in "$@"; do
        [[ -n "$num" && "$num" != "-" ]] || continue
        node="$(disk_part_name "$disk" "$num")"
        uuid="$(blkid -s UUID -o value "$node" 2>/dev/null)" || continue
        [[ -n "$uuid" ]] || continue
        if [[ ! -e "/dev/disk/by-uuid/$uuid" ]]; then
            run_exec disk mkdir -p /dev/disk/by-uuid
            run_exec disk ln -sf "../../${node##*/}" "/dev/disk/by-uuid/$uuid"
        fi
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
    # debootstrap needs a usable /dev in the target and manages /proc and
    # /dev/pts on its own; pre-binding them breaks its second-stage cleanup.
    disk_ensure_uuid_links "$disk" "$boot_n" "$swap_n" "$root_n"
    run_exec disk mkdir -p "$target/dev" || return 1
    run_exec disk mount --bind /dev "$target/dev" || return 1
}

# После бутстрапа chroot-финализации (grub-install, systemd-firstboot) нужны
# proc, sys и pts: монтируем их отдельным шагом, когда debootstrap уже сам
# разобрался со своими точками монтирования.
disk_bind_for_chroot() {
    local target="$1"
    run_exec disk mkdir -p "$target/proc" "$target/sys" "$target/dev/pts" || return 1
    run_exec disk mount --bind /proc "$target/proc" || return 1
    run_exec disk mount --bind /sys "$target/sys" || return 1
    run_exec disk mount -t devpts devpts "$target/dev/pts" || return 1
}
