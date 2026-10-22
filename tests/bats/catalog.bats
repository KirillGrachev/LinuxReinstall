#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/catalog.sh
source "$LRI_ROOT/lib/catalog.sh"

@test "debian slug resolves to debootstrap with codename" {
    catalog_resolve debian-12
    [ "$LRI_CAT_FAMILY" = "debootstrap" ]
    [ "$LRI_CAT_RELEASE" = "bookworm" ]
    [[ "$LRI_CAT_MIRROR" == *"deb.debian.org"* ]]
    [ "$LRI_CAT_KERNEL" = "linux-image-amd64" ]
}

@test "rocky and alma resolve to the dnf family" {
    catalog_resolve rocky-9
    [ "$LRI_CAT_FAMILY" = "dnf" ]
    catalog_resolve alma-9
    [ "$LRI_CAT_FAMILY" = "dnf" ]
}

@test "proxmox is its own family on top of debian" {
    catalog_resolve proxmox-8
    [ "$LRI_CAT_FAMILY" = "proxmox" ]
    [ "$LRI_CAT_RELEASE" = "bookworm" ]
}

@test "every catalog family is one the bootstrap layer knows" {
    local row slug family release mirror
    for row in "${CATALOG[@]}"; do
        read -r slug family release mirror kernel <<< "$row"
        case "$family" in
            debootstrap|dnf|zypper|pacstrap|apk|proxmox) ;;
            *) echo "unknown family $family for $slug"; return 1 ;;
        esac
    done
}

@test "unknown slug returns 1" {
    run catalog_resolve gentoo-latest
    [ "$status" -eq 1 ]
}

@test "catalog list prints every slug" {
    run catalog_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"debian-12"* ]]
    [[ "$output" == *"alpine-3.21"* ]]
    [[ "$output" == *"opensuse-tumbleweed"* ]]
}

@test "entry point rejects unknown distro with code 2" {
    run "$LRI_ROOT/reinstall.sh" --distro gentoo-latest --disk /dev/sda --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown distro: gentoo-latest"* ]]
}

@test "entry point lists the catalog" {
    run "$LRI_ROOT/reinstall.sh" --list-distros
    [ "$status" -eq 0 ]
    [[ "$output" == *"SLUG"* ]]
    [[ "$output" == *"arch-linux"* ]]
}
