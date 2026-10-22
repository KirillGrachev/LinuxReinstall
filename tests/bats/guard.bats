#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/guard.sh
source "$LRI_ROOT/lib/guard.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
    printf "/dev/sda1 / ext4 rw 0 0\n/dev/sdb1 /mnt/data ext4 rw 0 0\n" > "$LRI_TMP/mounts"
    LRI_MOUNTS_FILE="$LRI_TMP/mounts"
}
teardown() { rm -rf "$LRI_TMP"; }

@test "mounted target is refused with code 2" {
    LRI_DRY_RUN=0
    run guard_disk_free /dev/sdb
    [ "$status" -eq 2 ]
    [[ "$output" == *"is mounted"* ]]
}

@test "partition of a mounted disk is refused too" {
    LRI_DRY_RUN=0
    run guard_disk_free /dev/sda
    [ "$status" -eq 2 ]
}

@test "unmounted target passes" {
    LRI_DRY_RUN=0
    touch "$LRI_TMP/disk.img"
    run guard_disk_free "$LRI_TMP/disk.img"
    [ "$status" -eq 0 ]
}

@test "dry-run tolerates a missing disk with a journal note" {
    LRI_DRY_RUN=1
    run guard_disk_free /dev/nosuch
    [ "$status" -eq 0 ]
    grep -qP "^guard\tdisk-missing\t/dev/nosuch" "$LRI_TMP/journal.tsv"
}

@test "non-root real run is refused with code 2" {
    LRI_DRY_RUN=0
    if (( EUID == 0 )); then skip "running as root, cannot test the refusal"; fi
    run guard_root
    [ "$status" -eq 2 ]
}

@test "dry-run skips the root requirement" {
    LRI_DRY_RUN=1
    run guard_root
    [ "$status" -eq 0 ]
}

@test "confirm declines without yes and changes nothing" {
    LRI_DRY_RUN=0 LRI_YES=0
    run bash -c "source $LRI_ROOT/lib/log.sh; source $LRI_ROOT/lib/guard.sh; LRI_DRY_RUN=0; LRI_YES=0; echo no | guard_confirm summary"
    [ "$status" -eq 3 ]
}

@test "confirm passes on --yes" {
    LRI_DRY_RUN=0 LRI_YES=1
    run guard_confirm "summary"
    [ "$status" -eq 0 ]
}

@test "dry-run exec journals the exact command line" {
    LRI_DRY_RUN=1
    run_exec disk wipefs -a /dev/sdc
    grep -qP "^disk\texec\twipefs -a /dev/sdc\tdry-run$" "$LRI_TMP/journal.tsv"
}

@test "dry-run write journals path and size without touching disk" {
    LRI_DRY_RUN=1
    run_write_file net /etc/network/interfaces "auto lo"
    [ ! -e /etc/network/interfaces.lri-test ]
    grep -qP "^net\twrite\t/etc/network/interfaces\t" "$LRI_TMP/journal.tsv"
}
