#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"
# shellcheck source=lib/run.sh
source "$LRI_ROOT/lib/run.sh"
# shellcheck source=lib/net.sh
source "$LRI_ROOT/lib/net.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
    LRI_DRY_RUN=1
}
teardown() { rm -rf "$LRI_TMP"; }

@test "debian static render carries address gateway and dns" {
    run net_render_debian static eth0 192.0.2.10/24 192.0.2.1 1.1.1.1 9.9.9.9
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto eth0"* ]]
    [[ "$output" == *"iface eth0 inet static"* ]]
    [[ "$output" == *"address 192.0.2.10/24"* ]]
    [[ "$output" == *"gateway 192.0.2.1"* ]]
    [[ "$output" == *"dns-nameservers 9.9.9.9"* ]]
}

@test "debian dhcp render is a single stanza" {
    run net_render_debian dhcp eth0 "" ""
    [[ "$output" == *"iface eth0 inet dhcp"* ]]
    [[ "$output" != *"address"* ]]
}

@test "networkd static render uses Address Gateway DNS keys" {
    run net_render_networkd static eth0 192.0.2.10/24 192.0.2.1 1.1.1.1
    [[ "$output" == *"[Match]"* ]]
    [[ "$output" == *"Name=eth0"* ]]
    [[ "$output" == *"Address=192.0.2.10/24"* ]]
    [[ "$output" == *"Gateway=192.0.2.1"* ]]
    [[ "$output" == *"DNS=1.1.1.1"* ]]
}

@test "debian family writes interfaces, rpm family writes networkd unit" {
    LRI_NETWORK=static LRI_NET_IFACE=eth0 LRI_NET_ADDRESS=192.0.2.10/24 LRI_NET_GATEWAY=192.0.2.1 LRI_NET_DNS=(1.1.1.1)
    net_apply /mnt/target debootstrap
    grep -qP "^net\twrite\t/mnt/target/etc/network/interfaces" "$LRI_TMP/journal.tsv"
    : > "$LRI_TMP/journal.tsv"
    net_apply /mnt/target dnf
    grep -qP "^net\twrite\t/mnt/target/etc/systemd/network/10-lri.network" "$LRI_TMP/journal.tsv"
}

@test "capture honours environment overrides without touching the system" {
    LRI_NET_IFACE=eth7 LRI_ADDRESS=203.0.113.5/24 LRI_GATEWAY=203.0.113.1 LRI_DNS=(8.8.8.8)
    net_capture
    [ "$LRI_NET_IFACE" = "eth7" ]
    [ "$LRI_NET_ADDRESS" = "203.0.113.5/24" ]
    [ "$LRI_NET_GATEWAY" = "203.0.113.1" ]
    [ "${LRI_NET_DNS[0]}" = "8.8.8.8" ]
}
