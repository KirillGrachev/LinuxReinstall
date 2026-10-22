#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/log.sh
source "$LRI_ROOT/lib/log.sh"

setup() {
    LRI_TMP="$(mktemp -d)"
    log_init "$LRI_TMP/run.log" 0
    log_journal_init "$LRI_TMP/journal.tsv"
}

teardown() { rm -rf "$LRI_TMP"; }

@test "info and error land in the log file with levels" {
    log_info "hello there"
    log_error "bad thing"
    grep -q "\[INFO\] hello there" "$LRI_TMP/run.log"
    grep -q "\[ERROR\] bad thing" "$LRI_TMP/run.log"
}

@test "debug is silent unless verbose" {
    log_debug "hidden"
    ! grep -q "hidden" "$LRI_TMP/run.log"
    log_init "$LRI_TMP/run.log" 1
    log_debug "visible"
    grep -q "\[DEBUG\] visible" "$LRI_TMP/run.log"
}

@test "journal line is four TSV fields" {
    log_journal disk wipe /dev/sda "gpt, efi"
    run cat "$LRI_TMP/journal.tsv"
    [ "$status" -eq 0 ]
    [ "$(awk -F"\t" "{print NF}" "$LRI_TMP/journal.tsv")" = "4" ]
    grep -qP "^disk\twipe\t/dev/sda\tgpt, efi$" "$LRI_TMP/journal.tsv"
}

@test "journal is a no-op without init" {
    LRI_JOURNAL_FILE=""
    run log_journal disk wipe /dev/sda
    [ "$status" -eq 0 ]
}
