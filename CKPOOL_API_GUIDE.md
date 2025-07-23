# CKPool API Guide - Using ckpmsg

CKPool doesn't use a traditional HTTP API. Instead, it uses Unix domain sockets accessed via the `ckpmsg` utility. This guide explains how to query and control your CKPool instance.

## Prerequisites

- CKPool must be running
- You need access to the `ckpmsg` binary (installed with ckpool)
- Unix sockets must be accessible (typically in `/tmp/ckpool/`)

## Basic Usage

```bash
ckpmsg -s /tmp/ckpool/<process> <command>
```

Where `<process>` is one of:
- `stratifier` - Main mining process (most commands)
- `connector` - Network connections
- `generator` - Block generation
- `pool` - Main pool process

## Common Commands

### 1. Pool Statistics

Get overall pool statistics:
```bash
ckpmsg -s /tmp/ckpool/stratifier stats
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
ckpmsg -s /tmp/ckpool/stratifier users
```

Returns JSON array with all users and their statistics.

### 3. List All Workers

Get detailed worker information:
```bash
ckpmsg -s /tmp/ckpool/stratifier workers
```

Returns JSON with all workers grouped by user.

### 4. Get Specific User Info

Get information about a specific user:
```bash
ckpmsg -s /tmp/ckpool/stratifier user.info=USERNAME
```

Example:
```bash
ckpmsg -s /tmp/ckpool/stratifier user.info=skaisser
```

### 5. Get Current Work

View the current work template:
```bash
ckpmsg -s /tmp/ckpool/stratifier current.workbase
```

### 6. Change Log Level

Adjust logging verbosity:
```bash
# Set to debug
ckpmsg -s /tmp/ckpool/stratifier loglevel=7

# Set to notice (default)
ckpmsg -s /tmp/ckpool/stratifier loglevel=5

# Set to warning only
ckpmsg -s /tmp/ckpool/stratifier loglevel=3
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
ckpmsg -s /tmp/ckpool/stratifier dropuser=USERNAME
```

### 8. Pool Summary

Get a quick summary:
```bash
ckpmsg -s /tmp/ckpool/pool summary
```

### 9. Shutdown Pool

Gracefully shutdown the pool:
```bash
ckpmsg -s /tmp/ckpool/pool shutdown
```

## Practical Examples

### Monitor Pool in Real-time

Create a monitoring script:
```bash
#!/bin/bash
while true; do
    clear
    echo "=== CKPool Stats ==="
    ckpmsg -s /tmp/ckpool/stratifier stats | jq '.'
    sleep 5
done
```

### Get User Hashrate

Extract specific user's hashrate:
```bash
ckpmsg -s /tmp/ckpool/stratifier user.info=skaisser | jq '.hashrate1m'
```

### List Active Workers

Show all active workers with hashrate:
```bash
ckpmsg -s /tmp/ckpool/stratifier workers | jq '.workers[] | {user: .user, worker: .worker, hashrate: .hashrate1m}'
```

### Export Stats to JSON File

Save pool statistics:
```bash
ckpmsg -s /tmp/ckpool/stratifier stats > pool_stats_$(date +%Y%m%d_%H%M%S).json
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
            ckpmsg -s /tmp/ckpool/stratifier stats
            ;;
        *"/users"*)
            ckpmsg -s /tmp/ckpool/stratifier users
            ;;
        *"/workers"*)
            ckpmsg -s /tmp/ckpool/stratifier workers
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
    cmd = ['ckpmsg', '-s', f'/tmp/ckpool/{socket}', command]
    result = subprocess.run(cmd, capture_output=True, text=True)
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
ckpmsg -s /tmp/ckpool/stratifier loglevel=7 2>&1
```

## Advanced Usage

### Custom Queries
You can send custom JSON-RPC style queries:
```bash
echo '{"method":"stats","params":[]}' | ckpmsg -s /tmp/ckpool/stratifier -
```

### Monitoring Script
Create a comprehensive monitoring script:
```bash
#!/bin/bash
# monitor.sh

echo "CKPool Monitor - $(date)"
echo "===================="

echo -e "\n📊 Pool Stats:"
ckpmsg -s /tmp/ckpool/stratifier stats | jq '{
    hashrate: .hashrate1m,
    workers: .workers,
    users: .users,
    shares: .accounted_shares,
    uptime: .elapsed
}'

echo -e "\n👥 Top Users by Hashrate:"
ckpmsg -s /tmp/ckpool/stratifier users | jq -r '.users | 
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