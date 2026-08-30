# CKPool API Guide - Using ckpmsg

CKPool doesn't use a traditional HTTP API. Instead, it uses Unix domain sockets accessed via the `ckpmsg` utility. This guide explains how to query and control your CKPool instance.

## Prerequisites

- CKPool must be running
- You need access to the `ckpmsg` binary (installed with ckpool)
- Unix sockets must be accessible (typically in `/tmp/ckpool/`)

## Basic Usage

```bash
printf '<command>\n' | ckpmsg -s <parent> -n <pool-name> -N <process>
```

Two things about `ckpmsg` are easy to get wrong, and both fail **silently**:

1. **The command is read from stdin, not argv** (`src/ckpmsg.c:121`). A trailing
   `ckpmsg ... stats` is ignored and you get empty output with exit status 0.
2. **The socket path is assembled from three flags** as `<-s>/<-n>/<-N>`
   (`src/ckpmsg.c:252-262`) — `-s` is a *parent* directory, not the socket itself.

With the default `"sockdir": "/tmp/ckpool"`, the stratifier socket is
`/tmp/ckpool/stratifier`, so the flags are `-s /tmp -n ckpool -N stratifier`.
For any other sockdir, either split it into parent and basename, or point `-n`
at the current directory:

```bash
printf 'stats\n' | ckpmsg -s /var/run/mypool -n . -N stratifier
```

### A shell helper you will want

`ckpmsg` is a debugging tool, not a JSON transport. It writes its logging to
**stdout**, mixed in with the reply, and it prints through `LOGMSGSIZ`, which
emits at most 510 characters per line — so any sizeable response arrives split
across several lines behind two lines of chatter. Piping it straight into `jq`
fails on anything bigger than a toy pool.

```bash
ckpmsg_json() {
    printf '%s\n' "$1" \
        | ckpmsg -s /tmp -n ckpool -N "${2:-stratifier}" 2>/dev/null \
        | sed -n '/Received response: /,$p' \
        | sed '1s/^.*Received response: //' \
        | tr -d '\n'
}

ckpmsg_json stats | jq .
ckpmsg_json users | jq '.users | length'
```

> For anything programmatic — a dashboard, monitoring, a web app — prefer the
> read-only HTTP service in [`api/`](api/README.md). It returns clean JSON over
> an authenticated socket and does not require shell access to the pool host.

Where `<process>` is one of:
- `stratifier` - Main mining process (most commands)
- `connector` - Network connections
- `generator` - Block generation
- `pool` - Main pool process

## Common Commands

### 1. Pool Statistics

Get overall pool statistics:
```bash
printf 'stats\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

Returns JSON with:
- Current hashrate (1m, 5m, 15m, 1h, 1d, 7d)
- Number of connected workers and users
- Total shares submitted
- Pool uptime
- Share statistics

### 2. List All Users

Get a list of all users:
```bash
printf 'users\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

Returns JSON array with all users and their statistics.

### 3. List All Workers

Get detailed worker information:
```bash
printf 'workers\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

Returns JSON with all workers grouped by user.

### 4. Get Specific User Info

Get information about a specific user:
```bash
printf 'user.info=USERNAME\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

Example:
```bash
printf 'user.info=skaisser\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

### 5. Get Current Work

View the current work template:
```bash
printf 'current.workbase\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

### 6. Change Log Level

Adjust logging verbosity:
```bash
# Set to debug
printf 'loglevel=7\n' | ckpmsg -s /tmp -n ckpool -N stratifier

# Set to notice (default)
printf 'loglevel=5\n' | ckpmsg -s /tmp -n ckpool -N stratifier

# Set to warning only
printf 'loglevel=3\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

Log levels:
- 0: EMERG
- 1: ALERT
- 2: CRIT
- 3: ERR
- 4: WARNING
- 5: NOTICE
- 6: INFO
- 7: DEBUG

### 7. Disconnect User/Worker

Disconnect a specific user:
```bash
printf 'dropuser=USERNAME\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

### 8. Pool Summary

Get a quick summary:
```bash
printf 'summary\n' | ckpmsg -s /tmp -n ckpool -N pool
```

### 9. Shutdown Pool

Gracefully shutdown the pool:
```bash
printf 'shutdown\n' | ckpmsg -s /tmp -n ckpool -N pool
```

## Practical Examples

### Monitor Pool in Real-time

Create a monitoring script:
```bash
#!/bin/bash
while true; do
    clear
    echo "=== CKPool Stats ==="
    ckpmsg_json stats stratifier | jq '.'
    sleep 5
done
```

### Get User Hashrate

Extract specific user's hashrate:
```bash
ckpmsg_json user.info=skaisser stratifier | jq '.hashrate1m'
```

### List Active Workers

Show all active workers with hashrate:
```bash
ckpmsg_json workers stratifier | jq '.workers[] | {user: .user, worker: .worker, hashrate: .hashrate1m}'
```

### Export Stats to JSON File

Save pool statistics:
```bash
printf 'stats\n' | ckpmsg -s /tmp -n ckpool -N stratifier > pool_stats_$(date +%Y%m%d_%H%M%S).json
```

## Creating a Web API Wrapper

If you need HTTP access, create a simple wrapper:

```bash
#!/bin/bash
# api-server.sh - Simple HTTP wrapper for ckpmsg

# Requires socat
while true; do
    echo -e "HTTP/1.1 200 OK\nContent-Type: application/json\n"
    case "$REQUEST" in
        *"/stats"*)
            printf 'stats\n' | ckpmsg -s /tmp -n ckpool -N stratifier
            ;;
        *"/users"*)
            printf 'users\n' | ckpmsg -s /tmp -n ckpool -N stratifier
            ;;
        *"/workers"*)
            printf 'workers\n' | ckpmsg -s /tmp -n ckpool -N stratifier
            ;;
        *)
            echo '{"error":"Unknown endpoint"}'
            ;;
    esac
done | socat TCP-LISTEN:8080,reuseaddr,fork EXEC:"/bin/bash api-server.sh"
```

## Python Example

Query CKPool from Python:
```python
import subprocess
import json

def ckpool_command(socket, command):
    """Execute ckpmsg command and return parsed JSON"""
    cmd = ['ckpmsg', '-s', '/tmp', '-n', 'ckpool', '-N', socket]
    # ckpmsg reads the command from stdin -- passing it in argv is ignored.
    result = subprocess.run(cmd, input=command + '\n',
                            capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    return None

# Get pool stats
stats = ckpool_command('stratifier', 'stats')
print(f"Pool hashrate: {stats['hashrate1m']} GH/s")

# Get all users
users = ckpool_command('stratifier', 'users')
for user in users['users']:
    print(f"User: {user['user']}, Hashrate: {user['hashrate1m']}")
```

## Troubleshooting

### Permission Denied
If you get permission errors:
```bash
ls -la /tmp/ckpool/
# Check socket permissions
```

### No Such File
If sockets don't exist:
```bash
# Check if ckpool is running
ps aux | grep ckpool

# Check ckpool logs
tail -f ~/ckpool/logs/ckpool.log
```

### Invalid JSON Response
Some commands may return text instead of JSON. Parse accordingly:
```bash
printf 'loglevel=7\n' | ckpmsg -s /tmp -n ckpool -N stratifier 2>&1
```

## Advanced Usage

### Custom Queries
You can send custom JSON-RPC style queries:
```bash
echo '{"method":"stats","params":[]}' | printf '-\n' | ckpmsg -s /tmp -n ckpool -N stratifier
```

### Monitoring Script
Create a comprehensive monitoring script:
```bash
#!/bin/bash
# monitor.sh

echo "CKPool Monitor - $(date)"
echo "===================="

echo -e "\n📊 Pool Stats:"
ckpmsg_json stats stratifier | jq '{
    hashrate: .hashrate1m,
    workers: .workers,
    users: .users,
    shares: .accounted_shares,
    uptime: .elapsed
}'

echo -e "\n👥 Top Users by Hashrate:"
ckpmsg_json users stratifier | jq -r '.users | 
    sort_by(-.hashrate1m) | 
    .[0:5] | 
    .[] | 
    "\(.user): \(.hashrate1m) GH/s"'

echo -e "\n⚡ Recent Blocks:"
tail -n 5 ~/ckpool/logs/ckpool.log | grep "BLOCK FOUND"
```

## Notes

- All responses are in JSON format unless otherwise noted
- Some commands may require specific pool modes (solo vs proxy)
- Commands are processed asynchronously - responses may have slight delays
- For production monitoring, implement proper error handling and rate limiting