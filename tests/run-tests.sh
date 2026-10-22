#!/usr/bin/env bash
#
# SYNOPSIS
#     Прогон всех bats-сьютов проекта.
#
# DESCRIPTION
#     Возвращает 1, если любой сьют упал: CI и оператор смотрят на код,
#     а не на текст сводки.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v bats >/dev/null 2>&1; then
    echo "[FATAL] bats not found; install it: apt-get install bats" >&2
    exit 2
fi

rc=0
total=0
failed=0
for suite in "$root"/tests/bats/*.bats; do
    echo "[..] $(basename "$suite")"
    if out="$(bats "$suite" 2>&1)"; then
        n="$(grep -c "^ok" <<<"$out")"
        total=$(( total + n ))
    else
        printf '%s\n' "$out"
        n="$(grep -c "^ok" <<<"$out")"
        total=$(( total + n ))
        failed=$(( failed + 1 ))
        rc=1
    fi
done
echo "Test summary"
echo "tests passed: ${total}, suites failed: ${failed}"
exit "$rc"
