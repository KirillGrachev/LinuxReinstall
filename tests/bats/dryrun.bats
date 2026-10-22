#!/usr/bin/env bats
load '../test_helper'

setup() {
    LRI_TMP="$(mktemp -d)"
    touch "$LRI_TMP/fake.img"
    export JOURNAL=/tmp/reinstall-journal.tsv
}
teardown() { rm -rf "$LRI_TMP"; }

@test "full dry-run exits 0 and journals the pipeline in order" {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA dry-run@test"
    [ "$status" -eq 0 ]
    local wipe bootstrap net fstab grub umount
    wipe=$(grep -n "wipefs -a" "$JOURNAL" | head -1 | cut -d: -f1)
    bootstrap=$(grep -n "debootstrap --arch=amd64" "$JOURNAL" | head -1 | cut -d: -f1)
    net=$(grep -nP "^net\twrite" "$JOURNAL" | head -1 | cut -d: -f1)
    fstab=$(grep -nP "^finalize\twrite\t/mnt/lri-target/etc/fstab" "$JOURNAL" | head -1 | cut -d: -f1)
    grub=$(grep -n "grub-install" "$JOURNAL" | head -1 | cut -d: -f1)
    umount=$(grep -n "umount -R /mnt/lri-target" "$JOURNAL" | head -1 | cut -d: -f1)
    [ -n "$wipe" ] && [ -n "$bootstrap" ] && [ -n "$net" ] && [ -n "$fstab" ] && [ -n "$grub" ] && [ -n "$umount" ]
    [ "$wipe" -lt "$bootstrap" ] && [ "$bootstrap" -lt "$net" ] && [ "$net" -lt "$fstab" ] && [ "$fstab" -lt "$grub" ] && [ "$grub" -lt "$umount" ]
}

@test "dry-run changes nothing on the fake disk" {
    before=$(wc -c < "$LRI_TMP/fake.img")
    run "$LRI_ROOT/reinstall.sh" --distro rocky-9 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA dry-run@test"
    [ "$status" -eq 0 ]
    [ "$(wc -c < "$LRI_TMP/fake.img")" = "$before" ]
    [ ! -d /mnt/lri-target/etc ]
}

@test "real run without an ssh key is refused with code 2" {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img"
    [ "$status" -eq 2 ]
    [[ "$output" == *"needs an SSH key"* ]]
}

@test "dry-run of the proxmox slug journals the pve repo write" {
    run "$LRI_ROOT/reinstall.sh" --distro proxmox-8 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA dry-run@test"
    [ "$status" -eq 0 ]
    grep -q "pve.list" "$JOURNAL"
}

@test "dry-run binds proc after the bootstrap, not before" {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA dry-run@test"
    [ "$status" -eq 0 ]
    local bootstrap procbind
    bootstrap=$(grep -n "debootstrap --arch=amd64" "$JOURNAL" | head -1 | cut -d: -f1)
    procbind=$(grep -n "mount --bind /proc /mnt/lri-target/proc" "$JOURNAL" | head -1 | cut -d: -f1)
    [ -n "$bootstrap" ] && [ -n "$procbind" ]
    [ "$bootstrap" -lt "$procbind" ]
}

@test "efi dry-run journals the removable fallback bootloader install" {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img"         --dry-run --yes --boot efi --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA efi@test"
    [ "$status" -eq 0 ]
    grep -q -- "--removable" "$JOURNAL"
}
