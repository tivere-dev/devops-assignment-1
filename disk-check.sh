#!/usr/bin/env bash
#
# disk-check.sh - Report disk usage for a path and compare it to a threshold.
#
# Usage: ./disk-check.sh <threshold> [path]
#   threshold  integer percentage from 1 to 100
#   path       filesystem path to inspect (default: /)
#
# Exit codes:
#   0  usage is below the threshold
#   1  usage has reached or exceeded the threshold
#   2  invalid input (missing/non-numeric/out-of-range threshold, bad path)
#   3  disk usage could not be determined (runtime failure)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/disk-check.log"

log() {
    local level="$1"; shift
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") <threshold> [path]

  threshold   Integer percentage between 1 and 100.
  path        Path to check (default: /).

Exit codes: 0 below threshold, 1 threshold reached, 2 invalid input, 3 runtime failure.
USAGE
}

invalid() {
    # Report an input problem, log it and exit with code 2.
    printf 'Error: %s\n\n' "$1" >&2
    usage >&2
    log ERROR "invalid input: $1"
    exit 2
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
    esac

    [[ $# -ge 1 ]] || invalid "threshold argument is required"
    [[ $# -le 2 ]] || invalid "too many arguments"

    local threshold="$1"
    local path="${2:-/}"

    # Only plain digits are accepted, which rules out values such as abc, 1.5 and -1.
    [[ "$threshold" =~ ^[0-9]+$ ]] || invalid "threshold '$threshold' is not a whole number"
    threshold=$((10#$threshold))   # base 10 so a leading zero is not read as octal
    (( threshold >= 1 && threshold <= 100 )) || invalid "threshold must be between 1 and 100 (got $threshold)"

    [[ -n "$path" ]] || invalid "path must not be empty"
    [[ -e "$path" ]] || invalid "path '$path' does not exist"
    [[ -r "$path" ]] || invalid "path '$path' is not readable"

    log INFO "disk check started (path=$path, threshold=${threshold}%)"

    # -P forces the portable single-line POSIX format regardless of df flavour.
    local df_output
    if ! df_output=$(df -P "$path" 2>/dev/null) || [[ -z "$df_output" ]]; then
        echo "Error: unable to read disk usage for '$path'" >&2
        log ERROR "df failed for path=$path"
        exit 3
    fi

    local filesystem size used avail usage mount
    read -r filesystem size used avail usage mount <<< "$(printf '%s\n' "$df_output" | awk 'NR==2')"
    usage="${usage%\%}"

    if ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        echo "Error: could not parse disk usage from df output" >&2
        log ERROR "unparseable df output for path=$path: $df_output"
        exit 3
    fi

    echo "Disk usage report"
    echo "-----------------"
    printf '%-14s %s\n' "Path:"       "$path"
    printf '%-14s %s\n' "Filesystem:" "$filesystem"
    printf '%-14s %s\n' "Mounted on:" "$mount"
    printf '%-14s %s\n' "Size:"       "$(( size / 1024 )) MiB"
    printf '%-14s %s\n' "Used:"       "$(( used / 1024 )) MiB"
    printf '%-14s %s\n' "Available:"  "$(( avail / 1024 )) MiB"
    printf '%-14s %s%%\n' "Usage:"    "$usage"
    printf '%-14s %s%%\n' "Threshold:" "$threshold"
    echo

    if (( usage < threshold )); then
        echo "OK: usage ${usage}% is below the ${threshold}% threshold"
        log INFO "OK path=$path usage=${usage}% threshold=${threshold}%"
        exit 0
    fi

    echo "WARNING: usage ${usage}% has reached the ${threshold}% threshold"
    log WARN "THRESHOLD REACHED path=$path usage=${usage}% threshold=${threshold}%"
    exit 1
}

main "$@"
