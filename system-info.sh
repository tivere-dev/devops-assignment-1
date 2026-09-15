#!/usr/bin/env bash
#
# system-info.sh - Display information about the local Linux system.
#
# Every value is collected from the running system at execution time.
# Linux sources (/proc, /etc/os-release, ip) are preferred; sensible
# fallbacks keep the script usable on other Unix-like systems.
#
# Usage: ./system-info.sh [-h|--help]
# Exit codes: 0 success, 2 invalid arguments

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/system-info.log"

log() {
    # Append a timestamped entry to the script log: [date time] [LEVEL] message
    local level="$1"; shift
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [-h|--help]

Displays hostname, current user, date/time, operating system, kernel,
uptime, CPU, memory and the current working directory.
USAGE
}

print_row() {
    printf '%-24s %s\n' "$1:" "$2"
}

get_hostname() {
    hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n
}

get_current_user() {
    id -un 2>/dev/null || printf '%s\n' "${USER:-unknown}"
}

get_os() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        ( . /etc/os-release && printf '%s\n' "${PRETTY_NAME:-${NAME:-Linux}}" )
    elif command -v sw_vers >/dev/null 2>&1; then
        printf '%s %s\n' "$(sw_vers -productName)" "$(sw_vers -productVersion)"
    else
        uname -s
    fi
}

get_uptime() {
    if [[ -r /proc/uptime ]]; then
        local secs
        secs=$(cut -d. -f1 /proc/uptime)
        printf '%d days, %d hours, %d minutes\n' \
            $((secs / 86400)) $((secs % 86400 / 3600)) $((secs % 3600 / 60))
    elif uptime -p >/dev/null 2>&1; then
        uptime -p
    else
        # Generic fallback: strip the load-average part of the classic uptime line.
        uptime | sed -E 's/^.* up +//; s/,[^,]*(user|load).*$//'
    fi
}

get_load_average() {
    if [[ -r /proc/loadavg ]]; then
        awk '{print $1", "$2", "$3" (1, 5, 15 min)"}' /proc/loadavg
    else
        uptime | sed -E 's/.*load averages?: *//'
    fi
}

get_cpu_model() {
    local model=""
    if [[ -r /proc/cpuinfo ]]; then
        model=$(awk -F': *' '/^(model name|Model|Hardware)[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo)
    fi
    if [[ -z "$model" ]] && command -v lscpu >/dev/null 2>&1; then
        model=$(lscpu 2>/dev/null | awk -F': *' '/^Model name/ {print $2; exit}')
    fi
    if [[ -z "$model" ]] && command -v sysctl >/dev/null 2>&1; then
        model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    fi
    printf '%s\n' "${model:-unknown}"
}

get_cpu_count() {
    nproc 2>/dev/null \
        || getconf _NPROCESSORS_ONLN 2>/dev/null \
        || sysctl -n hw.ncpu 2>/dev/null \
        || echo "unknown"
}

get_memory() {
    if [[ -r /proc/meminfo ]]; then
        awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
             END {printf "total %.1f GiB, used %.1f GiB, available %.1f GiB\n",
                  t/1048576, (t-a)/1048576, a/1048576}' /proc/meminfo
    elif command -v free >/dev/null 2>&1; then
        free -m | awk '/^Mem:/ {printf "total %d MiB, used %d MiB, free %d MiB\n", $2, $3, $4}'
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.memsize 2>/dev/null | awk '{printf "total %.1f GiB\n", $1/1073741824}'
    else
        echo "unknown"
    fi
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        "") ;;
        *)  printf 'Error: unexpected argument "%s"\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac

    log INFO "system-info started by $(get_current_user)"

    echo "=============================================="
    echo " System Information Report"
    echo "=============================================="
    print_row "Hostname"            "$(get_hostname)"
    print_row "Current user"        "$(get_current_user)"
    print_row "Date/time"           "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    print_row "Operating system"    "$(get_os)"
    print_row "Kernel version"      "$(uname -r)"
    print_row "Architecture"        "$(uname -m)"
    print_row "Uptime"              "$(get_uptime)"
    print_row "Load average"        "$(get_load_average)"
    print_row "CPU model"           "$(get_cpu_model)"
    print_row "CPU cores"           "$(get_cpu_count)"
    print_row "Memory"              "$(get_memory)"
    print_row "Working directory"   "$(pwd)"
    print_row "Shell"               "bash ${BASH_VERSION}"
    echo "=============================================="

    log INFO "system-info completed successfully (host=$(get_hostname), kernel=$(uname -r))"
}

main "$@"
