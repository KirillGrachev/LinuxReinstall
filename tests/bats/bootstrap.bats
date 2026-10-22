#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/catalog.sh
source "$LRI_ROOT/lib/catalog.sh"
# shellcheck source=lib/bootstrap.sh
LRI_ROOT="$LRI_ROOT" source "$LRI_ROOT/lib/bootstrap.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
    LRI_DRY_RUN=1
}
teardown() { rm -rf "$LRI_TMP"; }

@test "debootstrap backend journals release and mirror" {
    catalog_resolve debian-12
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    grep -q "debootstrap --arch=amd64" "$LRI_TMP/journal.tsv"
    grep -q "bookworm /mnt/target http://deb.debian.org/debian" "$LRI_TMP/journal.tsv"
}

@test "dnf backend journals installroot and releasever" {
    catalog_resolve rocky-9
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    grep -q -- "--installroot=/mnt/target" "$LRI_TMP/journal.tsv"
    grep -q -- "--releasever=9" "$LRI_TMP/journal.tsv"
}

@test "zypper backend adds the repo before installing" {
    catalog_resolve opensuse-leap-15.6
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    first_addrepo=$(grep -n "addrepo" "$LRI_TMP/journal.tsv" | head -1 | cut -d: -f1)
    first_install=$(grep -n "install --auto-agree" "$LRI_TMP/journal.tsv" | head -1 | cut -d: -f1)
    [ -n "$first_addrepo" ] && [ -n "$first_install" ]
    [ "$first_addrepo" -lt "$first_install" ]
}

@test "pacstrap backend keeps keys and skips fstab" {
    catalog_resolve arch-linux
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    grep -q "pacstrap -K -G -M /mnt/target base linux openssh grub" "$LRI_TMP/journal.tsv"
}

@test "apk backend pins the release repository" {
    catalog_resolve alpine-3.21
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    grep -q -- "--repository http://dl-cdn.alpinelinux.org/alpine/v3.21/main" "$LRI_TMP/journal.tsv"
}

@test "proxmox backend bootstraps debian then drops the pve repo" {
    catalog_resolve proxmox-8
    bootstrap_run "$LRI_CAT_FAMILY" /mnt/target
    grep -q "debootstrap --arch=amd64" "$LRI_TMP/journal.tsv"
    grep -qP "^bootstrap\twrite\t/mnt/target/etc/apt/sources.list.d/pve.list" "$LRI_TMP/journal.tsv"
}

@test "unknown family is a runtime error" {
    run bootstrap_run gentoo /mnt/target
    [ "$status" -eq 1 ]
    [[ "$output" == *"No bootstrap backend"* ]]
}
