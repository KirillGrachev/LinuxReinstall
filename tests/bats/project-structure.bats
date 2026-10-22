#!/usr/bin/env bats
load '../test_helper'
# shellcheck source=lib/catalog.sh
source "$LRI_ROOT/lib/catalog.sh"

@test "shellcheck passes on every shell file" {
    command -v shellcheck >/dev/null || skip "shellcheck not installed"
    run shellcheck -x "$LRI_ROOT/reinstall.sh" "$LRI_ROOT/tests/run-tests.sh" \
        "$LRI_ROOT"/lib/*.sh "$LRI_ROOT"/lib/bootstrap/*.sh
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "every catalog family has a bootstrap backend" {
    local row slug family release mirror
    while read -r slug family release mirror; do
        [ -f "$LRI_ROOT/lib/bootstrap/$family.sh" ] || { echo "no backend for $family"; return 1; }
    done < <(printf "%s\n" "${CATALOG[@]}")
}

@test "no dead functions in lib: every function is referenced elsewhere" {
    local name hits
    while IFS= read -r name; do
        hits="$(grep -rF "$name" "$LRI_ROOT/reinstall.sh" "$LRI_ROOT/lib" "$LRI_ROOT/tests" | grep -v "^\S*: *$name()" | wc -l)"
        [ "$hits" -gt 0 ] || { echo "dead function: $name"; return 1; }
    done < <(grep -rhoE '^[a-z_]+\(\)' "$LRI_ROOT"/lib/*.sh "$LRI_ROOT"/lib/bootstrap/*.sh | tr -d '()')
}

@test "no tabs in indentation, no CRLF, no BOM" {
    local f
    while IFS= read -r f; do
        if grep -qP '^\t' "$f"; then echo "tab indent: $f"; return 1; fi
        if grep -qU $'\r' "$f"; then echo "CRLF: $f"; return 1; fi
        if head -c 3 "$f" | grep -q $'\xef\xbb\xbf'; then echo "BOM: $f"; return 1; fi
    done < <(git -C "$LRI_ROOT" ls-files)
}

@test "entry point sources every top-level lib module" {
    local f base
    for f in "$LRI_ROOT"/lib/*.sh; do
        base="$(basename "$f")"
        grep -q "lib/$base" "$LRI_ROOT/reinstall.sh" || { echo "not sourced: $base"; return 1; }
    done
}
