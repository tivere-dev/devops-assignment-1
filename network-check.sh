#!/usr/bin/env bash
#
# network-check.sh - Resolve a host, test reachability and show local interfaces.
#
# Usage: ./network-check.sh <hostname-or-ip> [port]
#
# Exit codes:
#   0  host resolved and the connectivity check(s) succeeded
#   1  operational failure (could not resolve, ping failed, TCP port closed)
#   2  invalid input (missing host, malformed host, port outside 1-65535)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/network-check.log"
TIMEOUT_SECS=5

log() {
    local level="$1"; shift
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") <hostname-or-ip> [port]

  hostname-or-ip   Host to resolve and check (e.g. localhost, example.com, 8.8.8.8).
  port             Optional TCP port (1-65535) to test with a connect attempt.

Exit codes: 0 success, 1 network/operational failure, 2 invalid input.
USAGE
}

invalid() {
    printf 'Error: %s\n\n' "$1" >&2
    usage >&2
    log ERROR "invalid input: $1"
    exit 2
}

section() {
    printf '\n--- %s ---\n' "$1"
}

with_timeout() {
    # Run a command with a time limit. Uses timeout(1) when present, otherwise a
    # background watchdog, so slow resolvers cannot stall the script.
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    fi
    "$@" &
    local pid=$!
    # The watchdog must not inherit stdout, or a command substitution would wait for it.
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return "$rc"
}

valid_host() {
    # Hostnames/IPv4: labels of letters, digits, dots and hyphens with no leading or
    # trailing separator. IPv6 literals: hex digits and colons. Anything else is rejected.
    local host="$1"
    [[ ${#host} -le 253 ]] || return 1
    # All digits and dots: must be a dotted-quad IPv4 address with octets 0-255.
    if [[ "$host" =~ ^[0-9.]+$ ]]; then
        [[ "$host" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
        local octet
        for octet in "${BASH_REMATCH[@]:1}"; do
            (( 10#$octet <= 255 )) || return 1
        done
        return 0
    fi
    [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && return 0
    [[ "$host" =~ ^[0-9A-Fa-f:]+$ && "$host" == *:* ]] && return 0
    return 1
}

resolve_host() {
    # Print one address for the host, preferring IPv4. The system resolver (getent on
    # Linux, dscacheutil on macOS) is authoritative when present; DNS tools are fallbacks.
    local host="$1" addr=""
    if command -v getent >/dev/null 2>&1; then
        addr=$(with_timeout "$TIMEOUT_SECS" getent ahosts "$host" 2>/dev/null \
               | awk '$1 ~ /^[0-9.]+$/ && !v4 {v4=$1} NR==1 {first=$1} END {print (v4 != "" ? v4 : first)}')
    elif command -v dscacheutil >/dev/null 2>&1; then
        addr=$(with_timeout "$TIMEOUT_SECS" dscacheutil -q host -a name "$host" 2>/dev/null \
               | awk '/^ip_address:/ {v4=$2} /^ipv6_address:/ {v6=$2} END {print (v4 != "" ? v4 : v6)}')
    elif command -v dig >/dev/null 2>&1; then
        addr=$(dig +short +time=3 +tries=1 "$host" A 2>/dev/null | grep -E '^[0-9.]+$' | head -n 1)
    elif command -v host >/dev/null 2>&1; then
        addr=$(host -W 3 "$host" 2>/dev/null | awk '/has (IPv6 )?address/ {print $NF; exit}')
    elif command -v python3 >/dev/null 2>&1; then
        addr=$(with_timeout "$TIMEOUT_SECS" python3 -c \
               'import socket, sys; print(socket.getaddrinfo(sys.argv[1], None)[0][4][0])' "$host" 2>/dev/null)
    fi
    [[ -n "$addr" ]] && printf '%s\n' "$addr"
}

ping_host() {
    # Two echo requests with a short wait; the timeout flag differs between ping flavours.
    local host="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        ping -c 2 -t "$TIMEOUT_SECS" "$host"
    else
        ping -c 2 -W "$TIMEOUT_SECS" "$host"
    fi
}

tcp_check() {
    # Attempt a TCP connection with bash's built-in /dev/tcp, bounded by a timeout.
    local host="$1" port="$2"
    # shellcheck disable=SC2016  # $0/$1 are expanded by the inner bash, on purpose
    with_timeout "$TIMEOUT_SECS" bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$host" "$port" 2>/dev/null
}

show_interfaces() {
    if command -v ip >/dev/null 2>&1; then
        ip -brief address 2>/dev/null || ip address 2>/dev/null
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | grep -E '^[A-Za-z0-9]+:|^[[:space:]]+inet6? '
    elif [[ -d /sys/class/net ]]; then
        ls /sys/class/net
    else
        echo "No interface listing tool (ip/ifconfig) available"
    fi
}

show_default_route() {
    if command -v ip >/dev/null 2>&1; then
        ip route show default 2>/dev/null
    elif command -v netstat >/dev/null 2>&1; then
        netstat -rn 2>/dev/null | awk '$1 == "default" || $1 == "0.0.0.0" {print}'
    fi
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
    esac

    [[ $# -ge 1 ]] || invalid "host argument is required"
    [[ $# -le 2 ]] || invalid "too many arguments"

    local host="$1"
    local port="${2:-}"
    local status=0

    valid_host "$host" || invalid "'$host' is not a valid hostname or IP address"

    if [[ -n "$port" ]]; then
        [[ "$port" =~ ^[0-9]+$ ]] || invalid "port '$port' is not a whole number"
        port=$((10#$port))
        (( port >= 1 && port <= 65535 )) || invalid "port must be between 1 and 65535 (got $port)"
    fi

    log INFO "network check started (host=$host${port:+, port=$port})"
    echo "Network check for: $host${port:+ (port $port)}"

    section "Name resolution"
    local addr
    if addr=$(resolve_host "$host") && [[ -n "$addr" ]]; then
        echo "Resolved $host -> $addr"
        log INFO "resolved host=$host address=$addr"
    else
        echo "Could not resolve '$host'" >&2
        log ERROR "resolution failed for host=$host"
        section "Network interfaces"
        show_interfaces
        echo
        echo "RESULT: FAILED (name resolution)"
        exit 1
    fi

    section "Connectivity (ICMP ping)"
    if ! command -v ping >/dev/null 2>&1; then
        echo "ping is not installed; skipping ICMP check"
        log WARN "ping unavailable, ICMP check skipped for host=$host"
    elif ping_host "$host" >/dev/null 2>&1; then
        echo "Ping to $host ($addr) succeeded"
        log INFO "ping succeeded host=$host"
    else
        echo "Ping to $host ($addr) failed (host down or ICMP filtered)"
        log WARN "ping failed host=$host"
        # Without a port to test, ping is the only connectivity check, so this is a failure.
        [[ -n "$port" ]] || status=1
    fi

    if [[ -n "$port" ]]; then
        section "TCP connectivity"
        if tcp_check "$addr" "$port"; then
            echo "TCP port $port on $host is OPEN"
            log INFO "tcp open host=$host port=$port"
        else
            echo "TCP port $port on $host is CLOSED or unreachable"
            log WARN "tcp closed host=$host port=$port"
            status=1
        fi
    fi

    section "Network interfaces"
    show_interfaces
    local route
    route=$(show_default_route)
    if [[ -n "$route" ]]; then
        section "Default route"
        printf '%s\n' "$route"
    fi

    echo
    if (( status == 0 )); then
        echo "RESULT: OK"
        log INFO "network check completed successfully host=$host${port:+ port=$port}"
    else
        echo "RESULT: FAILED (connectivity)"
        log ERROR "network check failed host=$host${port:+ port=$port}"
    fi
    exit "$status"
}

main "$@"
