#!/usr/bin/env bats
load '../test_helper'

@test "--help exits 0 and prints the usage" {
    run cli_parse --help
    [ "$status" -eq 0 ]
    run cli_usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: reinstall.sh"* ]]
}

@test "--help sets the help action" {
    cli_parse --help
    [ "$LRI_ACTION" = "help" ]
}

@test "--version exits 0 and sets the version action" {
    run cli_parse --version
    [ "$status" -eq 0 ]
    cli_parse --version
    [ "$LRI_ACTION" = "version" ]
}

@test "unknown argument exits 2 and names itself" {
    run cli_parse --distro debian-12 --disk /dev/sda --no-such-flag
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown argument: --no-such-flag"* ]]
}

@test "option without a value exits 2" {
    run cli_parse --distro
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires a value"* ]]
}

@test "missing --distro exits 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --disk /dev/sda; cli_validate"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing required argument: --distro"* ]]
}

@test "missing --disk exits 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12; cli_validate"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing required argument: --disk"* ]]
}

@test "--ssh-key and --ssh-key-file together exit 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12 --disk /dev/sda --ssh-key x --ssh-key-file /etc/hostname; cli_validate"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not both"* ]]
}

@test "missing --ssh-key-file exits 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12 --disk /dev/sda --ssh-key-file /no/such/file; cli_validate"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Key file not found"* ]]
}

@test "static network without --address exits 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12 --disk /dev/sda --network static; cli_validate"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires --address"* ]]
}

@test "bad --boot and --swap values exit 2" {
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12 --disk /dev/sda --boot uefi; cli_validate"
    [ "$status" -eq 2 ]
    run bash -c "source $LRI_ROOT/lib/cli.sh; cli_parse --distro debian-12 --disk /dev/sda --swap lots; cli_validate"
    [ "$status" -eq 2 ]
}

@test "valid parse fills the globals and defaults" {
    cli_parse --distro debian-12 --disk /dev/sda --dry-run
    cli_validate
    [ "$LRI_DISTRO" = "debian-12" ]
    [ "$LRI_DISK" = "/dev/sda" ]
    [ "$LRI_NETWORK" = "dhcp" ]
    [ "$LRI_BOOT" = "auto" ]
    [ "$LRI_SWAP_MB" = "0" ]
    [ "$LRI_DRY_RUN" = "1" ]
}

@test "repeatable --dns collects every value" {
    cli_parse --distro debian-12 --disk /dev/sda --dns 1.1.1.1 --dns 9.9.9.9
    [ "${#LRI_DNS[@]}" -eq 2 ]
    [ "${LRI_DNS[1]}" = "9.9.9.9" ]
}
