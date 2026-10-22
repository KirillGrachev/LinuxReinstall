#!/usr/bin/env bats
load '../test_helper'

setup() {
    LRI_TMP="$(mktemp -d)"
    touch "$LRI_TMP/fake.img"
    export JOURNAL=/tmp/reinstall-journal.tsv
    : > "$JOURNAL"
    export LRI_FIXTURE_FILE="$LRI_TMP/fixtures.tsv"
    : > "$LRI_FIXTURE_FILE"
}
teardown() { rm -rf "$LRI_TMP"; }

KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA fail@test"

run_pipeline() {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "$KEY"
}

@test "mkfs failure stops the pipeline with code 1 before bootstrap" {
    printf 'mkfs.ext4*\t1\n' > "$LRI_FIXTURE_FILE"
    run_pipeline
    [ "$status" -eq 1 ]
    grep -q "wipefs -a" "$JOURNAL"
    grep -q "sfdisk --force" "$JOURNAL"
    ! grep -q "debootstrap --arch=amd64" "$JOURNAL"
}

@test "bootstrap failure stops before any network write" {
    printf 'debootstrap*\t1\n' > "$LRI_FIXTURE_FILE"
    run_pipeline
    [ "$status" -eq 1 ]
    grep -q "debootstrap --arch=amd64" "$JOURNAL"
    ! grep -qP "^net\twrite" "$JOURNAL"
}

@test "fstab write failure stops before the bootloader" {
    printf 'write /mnt/lri-target/etc/fstab\t1\n' > "$LRI_FIXTURE_FILE"
    run_pipeline
    [ "$status" -eq 1 ]
    ! grep -q "grub-install" "$JOURNAL"
}

@test "journal records the fixture rc next to the dry-run mark" {
    printf 'partx*\t7\n' > "$LRI_FIXTURE_FILE"
    run_pipeline
    [ "$status" -eq 1 ]
    grep -q "dry-run rc=7" "$JOURNAL"
}

@test "without fixtures the dry-run pipeline still exits 0" {
    run_pipeline
    [ "$status" -eq 0 ]
}
