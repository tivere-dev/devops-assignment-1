# Assignment 1 – Linux, Bash & Networking Diagnostic Toolkit

A small toolkit of Bash scripts that collects system information, checks disk usage
against a threshold and performs basic network diagnostics. Every value is read from
the running system at execution time; nothing is hardcoded. Each script writes a
timestamped log entry under `logs/`.

## Contents

| File | Purpose |
|------|---------|
| `system-info.sh` | Prints hostname, user, date/time, OS, kernel, uptime, CPU, memory and working directory |
| `disk-check.sh` | Reports disk usage for a path and compares it with a percentage threshold |
| `network-check.sh` | Validates and resolves a host, pings it, optionally tests a TCP port, lists interfaces |
| `grade.sh` | The official local grader supplied with the assignment (unmodified) |
| `logs/` | Runtime logs (`system-info.log`, `disk-check.log`, `network-check.log`) and a committed example run |

## Requirements

- Linux (tested on Ubuntu 24.04 via GitHub-hosted runners) with Bash 4 or newer.
  The scripts also run on macOS/Bash 3.2 for local development.
- Standard utilities: `df`, `awk`, `sed`, `grep`, `uname`, `date`, `hostname`.
- For `network-check.sh`: `ping`, and one of `getent` (Linux), `dscacheutil` (macOS),
  `dig`, `host` or `python3` for name resolution. `ip` or `ifconfig` for interface details.
  `timeout` is used when available; otherwise a built-in watchdog bounds slow lookups.
- Git (for the history checks in `grade.sh`).

## Setup

```bash
git clone <your-repository-url>
cd assignment-1
chmod +x grade.sh *.sh
```

The executable bit is committed, so `chmod` is only needed if the files were copied
without permissions.

## Usage

### system-info.sh

```bash
./system-info.sh
```

```
==============================================
 System Information Report
==============================================
Hostname:                build-host
Current user:            devops
Date/time:               2026-09-15 20:14:02 UTC
Operating system:        Ubuntu 24.04.1 LTS
Kernel version:          6.8.0-1017-azure
Architecture:            x86_64
Uptime:                  0 days, 0 hours, 4 minutes
Load average:            0.52, 0.31, 0.12 (1, 5, 15 min)
CPU model:               AMD EPYC 7763 64-Core Processor
CPU cores:               4
Memory:                  total 15.6 GiB, used 1.2 GiB, available 14.4 GiB
Working directory:       /home/devops/assignment-1
Shell:                   bash 5.2.21(1)-release
==============================================
```

### disk-check.sh

```bash
./disk-check.sh <threshold> [path]
```

- `threshold` – integer percentage from 1 to 100 (required).
- `path` – any existing path; the filesystem that contains it is checked. Defaults to `/`.

```bash
./disk-check.sh 80          # check / against 80 %
./disk-check.sh 90 /var     # check the filesystem holding /var
```

```
Disk usage report
-----------------
Path:          /
Filesystem:    /dev/root
Mounted on:    /
Size:          74244 MiB
Used:          47010 MiB
Available:     27218 MiB
Usage:         64%
Threshold:     80%

OK: usage 64% is below the 80% threshold
```

### network-check.sh

```bash
./network-check.sh <hostname-or-ip> [port]
```

```bash
./network-check.sh localhost           # resolve, ping, list interfaces
./network-check.sh example.com 443     # additionally test TCP port 443
./network-check.sh 8.8.8.8 53
```

The script prints the resolved address, the ping result, the TCP result (when a port
was given), the local interfaces and the default route, followed by a final
`RESULT: OK` or `RESULT: FAILED (...)` line.

All scripts accept `-h` / `--help`.

## Exit codes

| Script | 0 | 1 | 2 | 3 |
|--------|---|---|---|---|
| `system-info.sh` | information collected | – | unexpected argument | – |
| `disk-check.sh` | usage below threshold | usage reached/exceeded threshold | invalid threshold or path | `df` could not report usage |
| `network-check.sh` | host resolved and reachable (and port open, if given) | resolution, ping or TCP failure | missing/invalid host (incl. out-of-range IPv4 such as `999.1.1.1`) or port | – |

Invalid input (for example `abc`, `0`, `101`, `1.5`, `-1`, a missing argument, a
non-existent path, a port outside 1–65535) always produces exit code 2 with a usage
message on stderr. Operational failures such as an unreachable host use exit code 1 so
callers can tell "bad input" apart from "the network is down".

## Logging

Each script appends one line per significant event to its own file in `logs/`:

```
[2026-09-15 20:14:02] [INFO] disk check started (path=/, threshold=80%)
[2026-09-15 20:14:02] [INFO] OK path=/ usage=64% threshold=80%
[2026-09-15 20:14:05] [ERROR] invalid input: port '65536' must be between 1 and 65535
```

The format is `[timestamp] [LEVEL] description`, with levels `INFO`, `WARN` and
`ERROR`. The `logs/` directory is created automatically if it is missing. Generated
logs are ignored by Git (see `.gitignore`); `logs/example-run.log` is a committed copy
of a real session so the repository shows what the logging looks like.

## Testing

Run the supplied grader from the repository root:

```bash
chmod +x grade.sh *.sh
./grade.sh
```

It checks required files, Bash syntax, executable permissions, the `system-info.sh`
output, the `disk-check.sh` and `network-check.sh` argument validation, the presence of
a log file and the Git history (at least 5 commits, at least one non-main branch).

Useful manual checks:

```bash
./disk-check.sh abc; echo $?        # 2
./disk-check.sh 100 /; echo $?      # 0
./network-check.sh localhost abc; echo $?   # 2
./network-check.sh localhost; echo $?       # 0 (1 if ping is blocked)
```

## Git workflow

Work was done on feature branches (`feature/system-info`, `feature/disk-check`,
`feature/network-check`) that were merged into `main` with merge commits. The
branches are kept in the repository; `git log --oneline --graph --all` shows the
history. When pushing, include the branches with `git push --all`.

## Assumptions

- The scripts are run from a Bash shell on Linux; macOS fallbacks exist but are a
  convenience, not the target platform.
- `disk-check.sh` treats "usage equal to the threshold" as reached, so 80 % usage with
  a threshold of 80 is a warning (exit 1).
- ICMP may be filtered on some networks. When a port is supplied, the TCP result decides
  the exit code and a failed ping is only reported as a warning.
- Name resolution is bounded to 5 seconds per lookup so an unreachable DNS server cannot
  hang the script.

## Troubleshooting

- **`Permission denied`** – run `chmod +x *.sh`.
- **`ping` fails but the host is up** – ICMP is probably blocked. Supply a port to test TCP
  instead, for example `./network-check.sh host 443`.
- **`Could not resolve`** – check `/etc/resolv.conf` or try the IP address directly.
- **No interface information** – install `iproute2` (`ip`) or `net-tools` (`ifconfig`).
- **Logs are not written** – the script directory must be writable; the log location is
  always `logs/` next to the scripts, regardless of the current working directory.
