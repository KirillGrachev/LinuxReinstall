#!/usr/bin/env bats
load '../test_helper'

setup() {
    LRI_TMP="$(mktemp -d)"
    touch "$LRI_TMP/fake.img"
    export JOURNAL=/tmp/reinstall-journal.tsv
    : > "$JOURNAL"
}
teardown() { rm -rf "$LRI_TMP"; }

fingerprint() {
    md5sum /proc/mounts 2>/dev/null | cut -d' ' -f1
    ls /dev | md5sum | cut -d' ' -f1
    ls /mnt 2>/dev/null | md5sum | cut -d' ' -f1
    md5sum /etc/hostname /etc/resolv.conf 2>/dev/null | md5sum | cut -d' ' -f1
}

@test "dry-run leaves the system fingerprints untouched" {
    local before after
    before="$(fingerprint)"
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA iso@test"
    [ "$status" -eq 0 ]
    after="$(fingerprint)"
    [ "$before" = "$after" ] || { echo "before: $before"; echo "after:  $after"; return 1; }
}

@test "dry-run creates the journal and no target tree" {
    run "$LRI_ROOT/reinstall.sh" --distro debian-12 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA iso@test"
    [ "$status" -eq 0 ]
    [ -s "$JOURNAL" ]
    [ ! -e /mnt/lri-target/etc ]
    [ ! -e /mnt/lri-target/dev ]
}

@test "the fake disk image is byte-identical after the dry-run" {
    local before after
    before="$(md5sum < "$LRI_TMP/fake.img")"
    run "$LRI_ROOT/reinstall.sh" --distro alpine-3.21 --disk "$LRI_TMP/fake.img" \
        --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEYAAAA iso@test"
    [ "$status" -eq 0 ]
    after="$(md5sum < "$LRI_TMP/fake.img")"
    [ "$before" = "$after" ]
}
