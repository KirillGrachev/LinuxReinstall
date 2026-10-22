#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/disk.sh
source "$LRI_ROOT/lib/disk.sh"
# shellcheck source=lib/net.sh
source "$LRI_ROOT/lib/net.sh"
# shellcheck source=lib/finalize.sh
source "$LRI_ROOT/lib/finalize.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
}
teardown() { rm -rf "$LRI_TMP"; }

@test "every rendered sfdisk script passes sfdisk --no-act" {
    command -v sfdisk >/dev/null || skip "sfdisk not installed"
    truncate -s 3G "$LRI_TMP/img"
    local combo mode swap
    for combo in "efi 0" "efi 2048" "bios 0" "bios 1024"; do
        read -r mode swap <<< "$combo"
        disk_render_sfdisk "$mode" "$swap" > "$LRI_TMP/script"
        run sfdisk --no-act --force "$LRI_TMP/img" < "$LRI_TMP/script"
        [ "$status" -eq 0 ] || { echo "combo $combo failed: $output"; return 1; }
    done
}

@test "sshd drop-in passes sshd -T and carries the hardening" {
    command -v sshd >/dev/null || skip "sshd not installed"
    mkdir -p "$LRI_TMP/sshd_config.d"
    ssh-keygen -q -t ed25519 -N "" -f "$LRI_TMP/hostkey" <<< y >/dev/null
    printf 'Include %s/sshd_config.d/*\nHostKey %s\n' "$LRI_TMP" "$LRI_TMP/hostkey" > "$LRI_TMP/sshd_config"
    printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\nPubkeyAuthentication yes\n' \
        > "$LRI_TMP/sshd_config.d/00-LinuxReinstall.conf"
    run sshd -T -f "$LRI_TMP/sshd_config"
    [ "$status" -eq 0 ]
    grep -q "^permitrootlogin without-password$" <<< "$output"  # sshd -T canonicalizes prohibit-password
    grep -q "^passwordauthentication no$" <<< "$output"
    grep -q "^pubkeyauthentication yes$" <<< "$output"
}

@test "rendered interfaces file passes ifup --no-act for static and dhcp" {
    command -v ifup >/dev/null || skip "ifupdown not installed"
    net_render_debian static eth0 192.0.2.10/24 192.0.2.1 1.1.1.1 > "$LRI_TMP/interfaces"
    run ifup --no-act -i "$LRI_TMP/interfaces" eth0
    [ "$status" -eq 0 ]
    net_render_debian dhcp eth0 "" "" > "$LRI_TMP/interfaces"
    run ifup --no-act -i "$LRI_TMP/interfaces" eth0
    [ "$status" -eq 0 ]
}

@test "rendered fstab has six fields per line and unique mount points" {
    finalize_render_fstab UROOT UESP USWAP efi 2 > "$LRI_TMP/fstab"
    run awk 'NF != 6 { bad = 1 } END { exit bad }' "$LRI_TMP/fstab"
    [ "$status" -eq 0 ]
    [ "$(awk '{print $2}' "$LRI_TMP/fstab" | sort -u | wc -l)" = "$(awk '{print $2}' "$LRI_TMP/fstab" | wc -l)" ]
    grep -q "^UUID=UESP /boot/efi vfat" "$LRI_TMP/fstab"
    grep -q "^UUID=USWAP none swap" "$LRI_TMP/fstab"
}

@test "fstab without swap carries no swap line" {
    finalize_render_fstab UROOT UESP USWAP bios - > "$LRI_TMP/fstab"
    ! grep -q "swap" "$LRI_TMP/fstab"
    [ "$(wc -l < "$LRI_TMP/fstab")" = "1" ]
}
