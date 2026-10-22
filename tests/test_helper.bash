# Общий контекст сьютов: путь к проекту и загруженные библиотеки.
LRI_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
# shellcheck source=lib/cli.sh
source "$LRI_ROOT/lib/cli.sh"
