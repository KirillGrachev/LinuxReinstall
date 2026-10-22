#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/disk.sh
source "$LRI_ROOT/lib/disk.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
    LRI_DRY_RUN=1
}
teardown() { rm -rf "$LRI_TMP"; }

@test "efi layout: esp, optional swap, root" {
    run disk_render_sfdisk efi 0
    [ "$status" -eq 0 ]
    [[ "$output" == "label: gpt"* ]]
    [[ "$output" == *"type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp"* ]]
    [[ "$output" != *"name=swap"* ]]
    [[ "$output" == *"name=root"* ]]
}

@test "efi layout with swap inserts the swap partition second" {
    run disk_render_sfdisk efi 2048
    [[ "$output" == *"size=2048MiB, type=0657FD6D-A4AB-44C4-84E5-0933C84B4F4F, name=swap"* ]]
    local swap_line root_line
    swap_line="$(grep -n "name=swap" <<<"$output" | cut -d: -f1)"
    root_line="$(grep -n "name=root" <<<"$output" | cut -d: -f1)"
    [ "$swap_line" -lt "$root_line" ]
}

@test "bios layout starts with the bios_grub partition" {
    run disk_render_sfdisk bios 0
    [[ "$output" == *"type=21686148-6449-6E6F-744E-656564454649, name=biosboot"* ]]
}

@test "partition names get p suffix on nvme only" {
    [ "$(disk_part_name /dev/nvme0n1 3)" = "/dev/nvme0n1p3" ]
    [ "$(disk_part_name /dev/sda 3)" = "/dev/sda3" ]
}

@test "dry-run apply journals wipe, sfdisk and mkfs in order" {
    disk_apply /dev/sdc efi 0 "$LRI_TMP/sfdisk.txt"
    local wipe sfdisk mkfs
    wipe=$(grep -n "wipefs -a /dev/sdc" "$LRI_TMP/journal.tsv" | cut -d: -f1)
    sfdisk=$(grep -n "sfdisk --force /dev/sdc" "$LRI_TMP/journal.tsv" | cut -d: -f1)
    mkfs=$(grep -n "mkfs.ext4 -F /dev/sdc2" "$LRI_TMP/journal.tsv" | cut -d: -f1)
    [ -n "$wipe" ] && [ -n "$sfdisk" ] && [ -n "$mkfs" ]
    [ "$wipe" -lt "$sfdisk" ] && [ "$sfdisk" -lt "$mkfs" ]
}

@test "dry-run apply with swap formats the swap partition" {
    disk_apply /dev/sdc bios 1024 "$LRI_TMP/sfdisk.txt"
    grep -q "mkswap /dev/sdc2" "$LRI_TMP/journal.tsv"
    grep -q "mkfs.ext4 -F /dev/sdc3" "$LRI_TMP/journal.tsv"
}

@test "dry-run mount journals root and esp mounts" {
    disk_mount_target /dev/sdc efi 0 /mnt/target
    grep -q "mount /dev/sdc2 /mnt/target" "$LRI_TMP/journal.tsv"
    grep -q "mount /dev/sdc1 /mnt/target/boot/efi" "$LRI_TMP/journal.tsv"
}

@test "no sfdisk line starts with a comma" {
    for args in "efi 0" "efi 2048" "bios 0" "bios 1024"; do
        run bash -c "source $LRI_ROOT/lib/disk.sh; disk_render_sfdisk $args"
        [ "$status" -eq 0 ]
        while IFS= read -r line; do
            [[ "$line" != ,* ]]
        done <<< "$output"
    done
}
