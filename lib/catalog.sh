#!/usr/bin/env bash
#
# SYNOPSIS
#     Каталог дистрибутивов: слаг -> семейство бутстрапа, релиз, зеркало.
#
# DESCRIPTION
#     Одна таблица вместо размазанных по коду имён: добавить дистрибутив
#     значит добавить строку. Семейство определяет механизм бутстрапа
#     (lib/bootstrap/<family>.sh), релиз и зеркало передаются в него как есть.

# shellcheck disable=SC2034  # таблица читается резолвером и тестами
CATALOG=(
    # slug            family      release        mirror                           kernel
    "debian-12        debootstrap bookworm       http://deb.debian.org/debian     linux-image-amd64"
    "debian-13        debootstrap trixie         http://deb.debian.org/debian     linux-image-amd64"
    "ubuntu-22.04     debootstrap jammy          http://archive.ubuntu.com/ubuntu linux-image-generic"
    "ubuntu-24.04     debootstrap noble          http://archive.ubuntu.com/ubuntu linux-image-generic"
    "devuan-5         debootstrap daedalus       http://deb.devuan.org/merged     linux-image-amd64"
    "mint-22          debootstrap wilma          http://archive.ubuntu.com/ubuntu linux-image-generic"
    "kali-roll        debootstrap kali-rolling   http://http.kali.org/kali        linux-image-amd64"
    "proxmox-8        proxmox     bookworm       http://deb.debian.org/debian     linux-image-amd64"
    "fedora-42        dnf         42             http://download.fedoraproject.org/fedora kernel"
    "rocky-9          dnf         9              http://download.rockylinux.org/rocky kernel"
    "alma-9           dnf         9              http://mirrors.almalinux.org/almalinux kernel"
    "centos-stream-10 dnf         10             http://mirror.stream.centos.org/centos-stream kernel"
    "opensuse-leap-15.6 zypper     15.6          http://download.opensuse.org/distribution/leap kernel-default"
    "opensuse-tumbleweed zypper    tumbleweed    http://download.opensuse.org/tumbleweed kernel-default"
    "arch-linux       pacstrap    rolling        http://geo.mirror.pkgbuild.com   linux"
    "alpine-3.21      apk         3.21           http://dl-cdn.alpinelinux.org/alpine linux-lts"
)

catalog_list() {
    local row slug family release mirror
    printf "%-20s %-12s %-14s %-18s %s\n" "SLUG" "FAMILY" "RELEASE" "KERNEL" "MIRROR"
    for row in "${CATALOG[@]}"; do
        read -r slug family release mirror kernel <<< "$row"
        printf "%-20s %-12s %-14s %-18s %s\n" "$slug" "$family" "$release" "$kernel" "$mirror"
    done
}

# Резолвит слаг в семейство/релиз/зеркало; код 1 означает неизвестный слаг,
# и точка входа превращает его в код 2 с перечислением каталога.
catalog_resolve() {
    local want="$1" row slug family release mirror
    for row in "${CATALOG[@]}"; do
        read -r slug family release mirror kernel <<< "$row"
        if [[ "$slug" == "$want" ]]; then
            LRI_CAT_FAMILY="$family"
            LRI_CAT_RELEASE="$release"
            LRI_CAT_MIRROR="$mirror"
            LRI_CAT_KERNEL="$kernel"
            LRI_CAT_SLUG="$slug"
            return 0
        fi
    done
    return 1
}
