# ckpool-api — read-only HTTP API over ckpool's logs

A single-binary Go service that exposes ckpool's log tree over authenticated
HTTP, so an application (the BlockSniper Laravel app) can read pool state
without shell access to the pool host.

It lives in this repository **because it parses ckpool's output**: the log line
formats it greps for and the coinbase binary layout it decodes are defined by
`src/stratifier.c`. When those change, the parser has to change in the same
commit. Keeping it in a separate repo is how the two drift apart silently.

> This is **not** the same thing as [`CKPOOL_API_GUIDE.md`](../CKPOOL_API_GUIDE.md)
> in the repository root. That documents ckpool's own control interface — Unix
> domain sockets driven with `ckpmsg`, which can change pool state (set log
> level, disconnect a worker, shut the pool down). This service is read-only,
> speaks HTTP, and never touches those sockets.

## Endpoints

All require `Authorization: Bearer $CKPOOL_API_KEY`. Rate limited to 20
requests/minute per IP, responses cached 60s.

| Endpoint | Purpose |
|---|---|
| `GET /health` | liveness, log presence and size |
| `GET /tail?lines=N` | tail the main log (capped at 1000 lines) |
| `GET /grep?pattern=` | search the main log |
| `GET /find-block?height=N` | locate a solved block with context |
| `GET /stats` | parsed pool stats — hashrate, workers, users |
| `GET /user-log?user=&lines=N` | tail one miner's log |
| `GET /user-file?user=` | one miner's full status file |
| `GET /coinbase?user=NAME` | decode the coinbase this miner is currently working on — see [COINBASE_API.md](COINBASE_API.md) |
| `GET /metrics` | service-level counters |

## Configuration

Environment only. There is no config file.

| Variable | Default | Notes |
|---|---|---|
| `CKPOOL_API_KEY` | — | **required**; the server aborts without it |
| `CKPOOL_LOG_PATH` | `~/ckpool/logs/ckpool.log` | must match the pool's `logdir` |
| `CKPOOL_USER_LOGS_PATH` | `~/ckpool/logs/users` | ditto |
| `CKPOOL_API_PORT` | `8888` | |

Generate a key with `openssl rand -hex 32`. The server refuses to start on an
empty key **or** on the placeholder constant compiled into it — otherwise an
operator who forgot the variable would get a running service authenticated by a
value published in this repository, with the startup banner still reporting
`API Key: [SET]`.

## Build

Standard library only — no module dependencies, so no `go.sum` and no vendoring.

```bash
cd api
go build -ldflags="-s -w" -o ckpool-api .
```

Cross-compile for a server:

```bash
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ckpool-api-linux-amd64 .
GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o ckpool-api-linux-arm64 .
```

Binaries are **not** committed — they are built on demand and copied to the pool
host. Build on a Linux box rather than cross-compiling from macOS, so the
artifact is exercised on the same OS that runs it:

```bash
# from a checkout on the build host
cd api
gofmt -l . && go vet ./... && go build -ldflags="-s -w" -o ckpool-api .
scp ckpool-api solo:/tmp/ && ssh solo 'sudo install -m 0755 /tmp/ckpool-api /opt/ckpool-api/ckpool-api && sudo systemctl restart ckpool-api'
```

> ⚠️ **Ubuntu's apt Go is too old, and it does not fail loudly.** 24.04 ships
> `golang-go` **1.22**; `go.mod` requires **1.26.1**. Since Go 1.21 the default
> `GOTOOLCHAIN=auto` silently downloads the newer toolchain on first build —
> which works, but only with network access to the module proxy, and it prints
> nothing more than `go: downloading go1.26.1`. On an air-gapped or
> proxy-restricted host it fails instead. Install Go from
> <https://go.dev/dl/> if you want the version you asked for.

## Deploying

Prefer the release binary over building on the pool host.

```bash
# 1. Binary
sudo install -d -m 0755 /opt/ckpool-api
sudo install -m 0755 ckpool-api-linux-amd64 /opt/ckpool-api/ckpool-api

# 2. Key, root-only
sudo install -d -m 0755 /etc/ckpool-api
printf 'CKPOOL_API_KEY=%s\n' "$(openssl rand -hex 32)" \
    | sudo tee /etc/ckpool-api/ckpool-api.env >/dev/null
sudo chmod 0600 /etc/ckpool-api/ckpool-api.env

# 3. Point it at the pool's logs
sudo tee -a /etc/ckpool-api/ckpool-api.env >/dev/null <<'EOF'
CKPOOL_LOG_PATH=/home/ckpool/ckpool/logs/ckpool.log
CKPOOL_USER_LOGS_PATH=/home/ckpool/ckpool/logs/users
CKPOOL_API_PORT=8888
EOF

# 4. Unit — edit User=, WorkingDirectory= and ExecStart= first
sudo cp ckpool-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ckpool-api
```

Two things that reliably go wrong:

- **Run it as the user that runs ckpool.** ckpool creates its log directory mode
  `0750` (`src/ckpool.c`), so any other account gets `permission denied` on
  every endpoint while `/health` still answers.
- **Do not expose 8888 to the internet.** The key is the only authentication and
  it travels in cleartext over HTTP. Scope it in the firewall to the consuming
  application's address, exactly as the stratum host already does.

## Relationship to the Python server

`skaisser/ckpool_api` holds the original Python implementation, still installed
by `install-ckpool-api.sh` in the BlockSniper application repository. This Go
service supersedes it: one static binary, no interpreter, far lower latency and
memory, plus `/coinbase`, `/user-file` and `/metrics`, which Python never had.
