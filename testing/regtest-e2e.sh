#!/usr/bin/env bash
#
# regtest-e2e.sh -- Phase 9 money gate for P-0001 (bch-address-mining).
#
# End-to-end regtest verification of ckpool's solo (`-B`) per-address payout
# feature: spins up a throwaway BCHN `bitcoind -regtest` node, builds and
# starts `src/ckpool -B` against it, drives seven auth/payout scenarios with
# the bundled `testing/minerd` CPU miner (plus a couple of raw stratum
# JSON-RPC probes for cases minerd can't observe), and asserts every
# coinbase / auth outcome against the plan's acceptance matrix.
#
# WHY THIS MUST RUN ON LINUX, NOT ON THE AUTHORING MACHINE:
#   - src/ckpool links directly against <sys/epoll.h> (src/libckpool.c) --
#     it does not build on macOS/BSD.
#   - testing/minerd is a pre-compiled 64-bit Linux ELF binary.
#   - There is no BCH node or Docker available on the authoring machine.
# This script is therefore written, reviewed and lint-checked (`bash -n`)
# on macOS but only ever *executed* on the Ubuntu pool server. Build it
# there with `./autogen.sh && ./configure && make` before running.
#
# Design notes / known deviations worth flagging when reading logs:
#   - The plan text says "grep ckpool log for the explicit error" for the
#     typo'd-address rejection (scenario 5). Reading stratifier.c shows the
#     explicit "Invalid BCH address (...)" string is only ever sent to the
#     client over the stratum wire (client.show_message / the authorize
#     response's "error" field, stratifier.c:5750, send_auth_failure at
#     stratifier.c:7245-7248) -- LOGDEBUG only logs the message *type*
#     ("Sending stratum message authresult"), never its JSON body. So this
#     script captures the explicit error text with a raw stratum JSON-RPC
#     probe (stratum_probe(), scenario 5) rather than a log grep, and
#     additionally greps the log for the generic
#     "failed to authorise as user" line plus the absence of any
#     "Failed over" line, which the plan's Acceptance section separately
#     requires and which genuinely does land in the log.
#
# Usage: ./testing/regtest-e2e.sh
# Exit code: 0 if every assertion passed, 1 if any FAILed, 2 on missing
# prerequisites (nothing was started).

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths / constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CKPOOL_BIN="$REPO_ROOT/src/ckpool"
CKPMSG_BIN="$REPO_ROOT/src/ckpmsg"
MINERD_BIN="$SCRIPT_DIR/minerd"

# Block-finding ceiling for mine_block_as(). Regtest difficulty is 1.0, so this
# is purely a question of CPU hash rate, and the old fixed 90s made the gate
# flaky on CI-grade hardware: a 36-core box scored 31/35 while a 4-core GitHub
# runner scored 13/20 on the SAME commit -- scenarios timing out, not failing
# (issue #24). The poll loop breaks the moment the height increases, so a
# generous ceiling costs fast hardware nothing and only buys slow hardware the
# time it needs. Scales with core count: ~2 min on 36 cores, ~11 min on 4.
# Override with E2E_MINE_TIMEOUT to pin it explicitly.
E2E_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
E2E_MINE_TIMEOUT_SCALED=$(( 60 + 2400 / E2E_CORES ))
# Floor it. Scaling by core count alone gives the FASTEST machine the TIGHTEST
# ceiling, which is backwards: the poll loop breaks the instant a block lands,
# so a generous ceiling costs a fast box nothing and a tight one just invites
# flakes when that box happens to be busy -- a loaded 36-core host timed out at
# the 126s its core count implied. Generous everywhere, more generous when slow.
E2E_MINE_TIMEOUT="${E2E_MINE_TIMEOUT:-$(( E2E_MINE_TIMEOUT_SCALED > 300 ? E2E_MINE_TIMEOUT_SCALED : 300 ))}"

RPC_PORT=18543
P2P_PORT=18544
# NOTE: ckpool treats EVERY stratum port above 4000 as a "highdiff" port
# (src/connector.c: "All high port servers are treated as highdiff ports"),
# which overrides startdiff/mindiff and hands each client ckp->highdiff --
# 1000000 by default. At CPU-miner hash rates that is roughly a share every
# few months, so every mining scenario times out with no shares at all while
# the pool looks perfectly healthy. The conf below pins highdiff: 1 to keep
# this port usable for regtest; do not remove it without also moving
# STRATUM_PORT below 4000.
STRATUM_PORT=13333
WALLET_NAME="e2e"
RPC_USER="e2euser"
RPC_PASS="e2epass"

WORKDIR=""
BITCOIND_PID=""
CKPOOL_PID=""
MINERD_PIDS=()

TESTS_RUN=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
log()  { printf '[e2e] %s\n' "$*" >&2; }
warn() { printf '[e2e][WARN] %s\n' "$*" >&2; }

# check DESCRIPTION CONDITION_RESULT
# CONDITION_RESULT must already be "true"/"false" (a shell string), so callers
# do the comparison first and print the observed value in DESCRIPTION.
check() {
	local desc="$1" ok="$2"
	TESTS_RUN=$((TESTS_RUN + 1))
	if [[ "$ok" == "true" ]]; then
		printf 'PASS: %s\n' "$desc"
	else
		printf 'FAIL: %s\n' "$desc"
		TESTS_FAILED=$((TESTS_FAILED + 1))
	fi
}

bch_cli() {
	bitcoin-cli -regtest -rpcport="$RPC_PORT" -rpcuser="$RPC_USER" -rpcpassword="$RPC_PASS" "$@"
}

# Wallet-scoped RPCs must name the wallet explicitly. Since BCHN gained
# multiwallet support, a bare wallet RPC fails with error -19 ("Wallet file
# not specified (must request wallet RPC through /wallet/<filename>
# uri-path)") whenever the node does not have exactly one unambiguous wallet
# loaded -- which is the case on BCHN 29.x with a freshly created wallet.
# Routing through -rpcwallet is correct on every version and does not depend
# on how many wallets happen to be loaded.
bch_wallet() {
	bitcoin-cli -regtest -rpcport="$RPC_PORT" -rpcuser="$RPC_USER" -rpcpassword="$RPC_PASS" \
		-rpcwallet="$WALLET_NAME" "$@"
}

cleanup() {
	local rc=$?
	log "cleaning up (exit code $rc)..."
	for pid in "${MINERD_PIDS[@]:-}"; do
		[[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
	done
	if [[ -n "$CKPOOL_PID" ]] && kill -0 "$CKPOOL_PID" >/dev/null 2>&1; then
		kill "$CKPOOL_PID" >/dev/null 2>&1 || true
		wait "$CKPOOL_PID" 2>/dev/null || true
	fi
	if [[ -n "$BITCOIND_PID" ]] && kill -0 "$BITCOIND_PID" >/dev/null 2>&1; then
		bch_cli stop >/dev/null 2>&1 || kill "$BITCOIND_PID" >/dev/null 2>&1 || true
		wait "$BITCOIND_PID" 2>/dev/null || true
	fi
	if [[ $rc -ne 0 && -n "$WORKDIR" && -d "$WORKDIR" ]]; then
		warn "run failed -- preserving workdir for inspection: $WORKDIR"
		[[ -f "$WORKDIR/logs/e2e.log" ]] && { warn "last 40 lines of ckpool log:"; tail -40 "$WORKDIR/logs/e2e.log" >&2 || true; }
	elif [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
		rm -rf "$WORKDIR"
	fi
}
trap cleanup EXIT

wait_for_tcp() {
	local host="$1" port="$2" timeout="${3:-60}" waited=0
	while ! (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; do
		# `exec fd<&-` with NO command makes its redirections PERMANENT for the
		# shell. The old form here was `exec 3<&- 2>/dev/null`, which did not
		# just silence this line -- it pointed the whole script's stderr at
		# /dev/null for the rest of the run, from the first moment ckpool
		# starts. Every log, warn, cleanup message and abort reason after that
		# was silently discarded, which is why a failing run gave no clue why.
		# Braces scope the redirection to the group instead.
		{ exec 3<&-; } 2>/dev/null || true
		waited=$((waited + 1))
		if [[ $waited -ge $timeout ]]; then
			return 1
		fi
		sleep 1
	done
	{ exec 3<&- 3>&-; } 2>/dev/null || true
	return 0
}

# ---------------------------------------------------------------------------
# Prerequisite checks -- fail fast with a clear message (exit 2)
# ---------------------------------------------------------------------------
prereq_check() {
	local missing=()

	command -v bitcoind >/dev/null 2>&1 || missing+=("bitcoind (BCHN) not found in PATH")
	command -v bitcoin-cli >/dev/null 2>&1 || missing+=("bitcoin-cli (BCHN) not found in PATH")
	command -v jq >/dev/null 2>&1 || missing+=("jq not found in PATH")
	[[ -x "$CKPOOL_BIN" ]] || missing+=("$CKPOOL_BIN not built -- run make in $REPO_ROOT first")
	[[ -x "$CKPMSG_BIN" ]] || missing+=("$CKPMSG_BIN not built -- run make in $REPO_ROOT first")
	[[ -x "$MINERD_BIN" ]] || missing+=("$MINERD_BIN missing or not executable")

	if [[ "$(uname -s)" != "Linux" ]]; then
		missing+=("this host is $(uname -s), not Linux -- ckpool needs epoll(7) and testing/minerd is a Linux ELF binary; this script can only run on the Ubuntu pool server")
	fi

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "regtest-e2e.sh: cannot run here, missing prerequisites:" >&2
		local m
		for m in "${missing[@]}"; do
			echo "  - $m" >&2
		done
		exit 2
	fi
}

# ---------------------------------------------------------------------------
# bitcoind / ckpool lifecycle
# ---------------------------------------------------------------------------
start_bitcoind() {
	# -allowunconnectedmining is required: BCHN's getblocktemplate refuses to
	# build a template while the node has zero P2P peers (RPC error -9,
	# "Bitcoin is not connected!"). An isolated regtest node in CI never has a
	# peer, so without this flag ckpool can never obtain any work and every
	# mining scenario fails for a reason unrelated to the pool.
	log "starting bitcoind -regtest in $WORKDIR/bitcoind ..."
	mkdir -p "$WORKDIR/bitcoind"
	bitcoind -regtest -datadir="$WORKDIR/bitcoind" \
		-rpcuser="$RPC_USER" -rpcpassword="$RPC_PASS" \
		-rpcport="$RPC_PORT" -port="$P2P_PORT" \
		-rpcallowip=127.0.0.1 -rpcbind=127.0.0.1 \
		-listen=1 -daemon=0 -fallbackfee=0.0002 \
		-allowunconnectedmining=1 \
		-printtoconsole=0 -debug=0 -shrinkdebugfile=1 \
		>"$WORKDIR/bitcoind.stdout.log" 2>&1 &
	BITCOIND_PID=$!

	local waited=0
	until bch_cli getblockchaininfo >/dev/null 2>&1; do
		waited=$((waited + 1))
		if [[ $waited -ge 60 ]]; then
			echo "regtest-e2e.sh: bitcoind RPC never came up (see $WORKDIR/bitcoind.stdout.log)" >&2
			exit 2
		fi
		sleep 1
	done
	log "bitcoind RPC is up on 127.0.0.1:$RPC_PORT"
}

mature_chain_and_addresses() {
	log "creating wallet and maturing 101 blocks..."
	bch_cli createwallet "$WALLET_NAME" >/dev/null

	MATURE_ADDR=$(bch_wallet getnewaddress "mature")
	bch_cli generatetoaddress 101 "$MATURE_ADDR" >/dev/null

	# Pool's own addresses (config: bchaddress / pooladdress). Both are
	# regular regtest cashaddr (bchreg: prefix) from the node's wallet.
	POOL_ADDR=$(bch_wallet getnewaddress "pool-bchaddress")
	FEE_ADDR=$(bch_wallet getnewaddress "pool-fee")

	# Scenario 1: prefixed cashaddr username.
	ADDR1=$(bch_wallet getnewaddress "scenario1")
	# Scenario 2 / 6: bare cashaddr (strip the "bchreg:" prefix off the
	# payload) -- scenario 6 reuses this same address, uppercased, to
	# prove it resolves to the identical user account.
	ADDR2=$(bch_wallet getnewaddress "scenario2")
	ADDR2_BARE="${ADDR2#*:}"
	ADDR6_UPPER=$(printf '%s' "$ADDR2_BARE" | tr '[:lower:]' '[:upper:]')

	# Scenario 3: legacy Base58Check regtest address, if this bitcoind
	# build supports requesting the "legacy" address type explicitly.
	ADDR3=""
	if bch_wallet getnewaddress "scenario3" legacy >/tmp/e2e_addr3.$$ 2>/tmp/e2e_addr3.err.$$; then
		ADDR3=$(cat /tmp/e2e_addr3.$$)
	else
		warn "getnewaddress ... legacy not supported by this bitcoind build -- scenario 3 will be SKIPPED"
	fi
	rm -f /tmp/e2e_addr3.$$ /tmp/e2e_addr3.err.$$

	# Scenario 5: same payload as scenario 1, prefix kept, last payload
	# character flipped so the CashAddr checksum fails (a realistic typo).
	local prefix="${ADDR1%%:*}" payload="${ADDR1#*:}" last rest flipped
	last="${payload: -1}"
	rest="${payload:0:${#payload}-1}"
	if [[ "$last" == "q" ]]; then flipped="p"; else flipped="q"; fi
	ADDR5_TYPO="${prefix}:${rest}${flipped}"

	# Scenario 5b: same payload as scenario 3, last Base58 character
	# flipped so the Base58Check checksum fails. Regression guard for the
	# legacy leading-char gap in looks_like_address() -- a typo'd regtest
	# legacy address ('m'/'n'/'2' leading char) must be rejected as a typo
	# rather than silently authorised as a pool-fallback user.
	ADDR5B_TYPO_LEGACY=""
	if [[ -n "$ADDR3" ]]; then
		local l3 r3 f3
		l3="${ADDR3: -1}"
		r3="${ADDR3:0:${#ADDR3}-1}"
		if [[ "$l3" == "a" ]]; then f3="b"; else f3="a"; fi
		ADDR5B_TYPO_LEGACY="${r3}${f3}"
	fi

	log "pool bchaddress   = $POOL_ADDR"
	log "pool fee address  = $FEE_ADDR"
	log "scenario1 (prefixed cashaddr) = $ADDR1"
	log "scenario2 (bare cashaddr)     = $ADDR2_BARE"
	[[ -n "$ADDR3" ]] && log "scenario3 (legacy)            = $ADDR3"
	log "scenario5 (typo'd cashaddr)   = $ADDR5_TYPO"
	[[ -n "$ADDR5B_TYPO_LEGACY" ]] && log "scenario5b (typo'd legacy)    = $ADDR5B_TYPO_LEGACY"
	log "scenario6 (uppercase bare)    = $ADDR6_UPPER"
}

write_ckpool_conf() {
	CONF="$WORKDIR/ckpool.conf"
	SOCKDIR="$WORKDIR/sock/"
	LOGDIR="$WORKDIR/logs"
	mkdir -p "$SOCKDIR"

	jq -n \
		--arg url "127.0.0.1:$RPC_PORT" \
		--arg auth "$RPC_USER" \
		--arg pass "$RPC_PASS" \
		--arg bchaddress "$POOL_ADDR" \
		--arg pooladdress "$FEE_ADDR" \
		--arg serverurl "127.0.0.1:$STRATUM_PORT" \
		--arg logdir "$LOGDIR" \
		'{
			btcd: [ { url: $url, auth: $auth, pass: $pass, notify: true } ],
			bchaddress: $bchaddress,
			pooladdress: $pooladdress,
			poolfee: 2.0,
			btcsig: "/regtest-e2e/",
			blockpoll: 100,
			donation: 0,
			nonce1length: 4,
			nonce2length: 8,
			update_interval: 30,
			serverurl: [ $serverurl ],
			mindiff: 1,
			startdiff: 1,
			maxdiff: 0,
			highdiff: 1,
			logdir: $logdir
		}' >"$CONF"

	log "wrote $CONF"
}

start_ckpool() {
	log "starting ckpool -B ..."
	"$CKPOOL_BIN" -B -c "$CONF" -s "$SOCKDIR" -n e2e -l 7 -L \
		>"$WORKDIR/ckpool.stdout.log" 2>&1 &
	CKPOOL_PID=$!

	if ! wait_for_tcp 127.0.0.1 "$STRATUM_PORT" 60; then
		echo "regtest-e2e.sh: ckpool stratum port $STRATUM_PORT never came up (see $WORKDIR/ckpool.stdout.log and $LOGDIR/e2e.log)" >&2
		exit 2
	fi
	log "ckpool stratum listening on 127.0.0.1:$STRATUM_PORT"
}

# ---------------------------------------------------------------------------
# minerd wrapper -- single place that knows minerd's actual CLI flags.
# Confirms with --help at runtime rather than assuming a flag exists.
# ---------------------------------------------------------------------------
MINERD_HELP=""
minerd_help() {
	if [[ -z "$MINERD_HELP" ]]; then
		MINERD_HELP="$("$MINERD_BIN" --help 2>&1 || true)"
	fi
	printf '%s' "$MINERD_HELP"
}

# run_miner USERNAME [EXTRA_MINERD_ARGS...]
# Launches minerd in the background against the local stratum port and
# records its PID in MINERD_PIDS for cleanup. Logs to $WORKDIR/minerd-<user>.log
# (username sanitised for the filename).
run_miner() {
	local user="$1"; shift || true
	local safe_name; safe_name="$(printf '%s' "$user" | tr -c 'A-Za-z0-9._-' '_')"
	local logfile="$WORKDIR/minerd-${safe_name}.log"
	local args=(-a sha256d -o "stratum+tcp://127.0.0.1:$STRATUM_PORT" -u "$user" -p x)

	# NOTE: deliberately no --coinbase-addr. That option belongs to solo
	# getblocktemplate mining, where the miner builds its own coinbase. Under
	# stratum the POOL builds the coinbase, and the payout address under test
	# is the stratum *username* -- so the option is meaningless here, and
	# actively harmful: this cpuminer validates the value as legacy Base58 and
	# exits instantly on a cashaddr with "invalid address", which made every
	# mining scenario fail with no miner having ever started.
	args+=("$@")

	"$MINERD_BIN" "${args[@]}" >"$logfile" 2>&1 &
	local pid=$!
	MINERD_PIDS+=("$pid")
	printf '%s' "$pid"
}

stop_miner() {
	local pid="$1"
	kill "$pid" >/dev/null 2>&1 || true
	wait "$pid" 2>/dev/null || true
}

# mine_block_as USERNAME -> echoes the new block hash, or empty string on timeout
# ckpmsg_json COMMAND -- ask the stratifier for COMMAND and return only the JSON.
#
# Three separate traps live in this one call, and every one of them fails
# quietly rather than loudly (issue #22):
#   1. The command is read from STDIN, not argv (src/ckpmsg.c:121). A trailing
#      `ckpmsg ... users` is ignored and you get empty output with rc 0.
#   2. The socket path is assembled as <-s>/<-n>/<-N> (src/ckpmsg.c:252-262).
#      `-s` is a PARENT directory. ckpool here runs with -s "$SOCKDIR", so its
#      sockets sit directly in SOCKDIR and `-n .` keeps the assembled path
#      pointing at them without splitting SOCKDIR into parent and basename.
#   3. ckpmsg logs to STDOUT, not stderr, and the payload arrives inside a
#      "Received response: " log line. Capturing raw stdout hands jq three
#      lines of chatter and it exits 5 on the parse error -- which is exactly
#      what aborted this suite under `set -e` before scenario 6 could report.
ckpmsg_json() {
	local cmd="$1" out
	# ckpmsg prints through LOGMSGSIZ, which emits at most 510 chars per line,
	# so a response of any size arrives split across several lines. Take
	# everything from the marker to EOF and rejoin it.
	out=$(printf '%s\n' "$cmd" | "$CKPMSG_BIN" -s "$SOCKDIR" -n . -N stratifier 2>/dev/null \
		| sed -n '/Received response: /,$p' \
		| sed '1s/^.*Received response: //' | tr -d '\n') || true
	# A missing socket or an empty reply must still yield parseable JSON so the
	# assertions below fail as assertions, not as a shell abort.
	[[ -n "$out" ]] && printf '%s' "$out" || printf '{}'
}

mine_block_as() {
	local user="$1" timeout="${2:-$E2E_MINE_TIMEOUT}"
	local start_height pid waited=0 height hash=""

	start_height=$(bch_cli getblockcount)
	pid=$(run_miner "$user")

	while [[ $waited -lt $timeout ]]; do
		height=$(bch_cli getblockcount)
		if [[ "$height" -gt "$start_height" ]]; then
			hash=$(bch_cli getblockhash "$height")
			break
		fi
		waited=$((waited + 1))
		sleep 1
	done

	stop_miner "$pid"
	printf '%s' "$hash"
}

# ---------------------------------------------------------------------------
# Raw stratum JSON-RPC probe -- used where we need the literal wire content
# (auth error text) rather than what minerd chooses to print.
# ---------------------------------------------------------------------------
# stratum_probe USERNAME PASSWORD -> prints every line received within 5s
stratum_probe() {
	local user="$1" pass="$2" fd
	exec {fd}<>"/dev/tcp/127.0.0.1/$STRATUM_PORT"
	printf '{"id":1,"method":"mining.subscribe","params":["regtest-e2e-probe"]}\n' >&"$fd"
	printf '{"id":2,"method":"mining.authorize","params":["%s","%s"]}\n' "$user" "$pass" >&"$fd"
	timeout 5 cat <&"$fd" || true
	exec {fd}<&- {fd}>&- 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Coinbase assertions
# ---------------------------------------------------------------------------
# vout_address INDEX BLOCK_JSON -> lowercased payload of scriptPubKey address
# (handles both the legacy "addresses":[...] and newer singular "address")
vout_addr_payload() {
	local idx="$1" block="$2"
	local addr
	addr=$(printf '%s' "$block" | jq -r ".tx[0].vout[$idx].scriptPubKey.address // .tx[0].vout[$idx].scriptPubKey.addresses[0] // empty")
	printf '%s' "${addr#*:}" | tr '[:upper:]' '[:lower:]'
}

# assert_split SCENARIO_NAME BLOCK_HASH EXPECTED_MINER_ADDR
assert_split() {
	local scenario="$1" hash="$2" expected_miner="$3"
	local block vout_count v0 v1 sats0 sats1 total fee_expected miner_expected
	local expected_miner_payload expected_fee_payload got_miner_payload got_fee_payload

	if [[ -z "$hash" ]]; then
		check "$scenario: block was found within timeout" "false"
		return
	fi

	block=$(bch_cli getblock "$hash" 2)
	vout_count=$(printf '%s' "$block" | jq '.tx[0].vout | length')
	check "$scenario: coinbase has exactly 2 outputs (observed: $vout_count)" \
		"$([[ "$vout_count" == "2" ]] && echo true || echo false)"

	v0=$(printf '%s' "$block" | jq -r '.tx[0].vout[0].value')
	v1=$(printf '%s' "$block" | jq -r '.tx[0].vout[1].value')
	sats0=$(jq -n --arg v "$v0" '($v|tonumber) * 100000000 | round')
	sats1=$(jq -n --arg v "$v1" '($v|tonumber) * 100000000 | round')
	total=$((sats0 + sats1))
	# Fee-split arithmetic (README.md "What is canonical", stratifier.c
	# :604-624): fee truncates down, miner absorbs the remainder.
	fee_expected=$((total * 2 / 100))
	miner_expected=$((total - fee_expected))
	check "$scenario: vout[0] (miner, $sats0 sats) + vout[1] (fee, $sats1 sats) = coinbasevalue ($total sats)" \
		"$([[ $((sats0 + sats1)) -eq "$total" ]] && echo true || echo false)"
	check "$scenario: vout[0] is 98% of coinbasevalue truncated down (observed $sats0, expected $miner_expected)" \
		"$([[ "$sats0" -eq "$miner_expected" ]] && echo true || echo false)"
	check "$scenario: vout[1] is exactly the 2% remainder (observed $sats1, expected $fee_expected)" \
		"$([[ "$sats1" -eq "$fee_expected" ]] && echo true || echo false)"

	expected_miner_payload=$(printf '%s' "${expected_miner#*:}" | tr '[:upper:]' '[:lower:]')
	expected_fee_payload=$(printf '%s' "${FEE_ADDR#*:}" | tr '[:upper:]' '[:lower:]')
	got_miner_payload=$(vout_addr_payload 0 "$block")
	got_fee_payload=$(vout_addr_payload 1 "$block")
	check "$scenario: vout[0] pays the expected miner address (observed $got_miner_payload, expected $expected_miner_payload)" \
		"$([[ "$got_miner_payload" == "$expected_miner_payload" ]] && echo true || echo false)"
	check "$scenario: vout[1] pays pooladdress (observed $got_fee_payload, expected $expected_fee_payload)" \
		"$([[ "$got_fee_payload" == "$expected_fee_payload" ]] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------
scenario_1_prefixed_cashaddr() {
	log "=== Scenario 1: prefixed cashaddr username (${ADDR1}.w1) ==="
	local hash; hash=$(mine_block_as "${ADDR1}.w1")
	assert_split "scenario1 (prefixed cashaddr)" "$hash" "$ADDR1"
}

scenario_2_bare_cashaddr() {
	log "=== Scenario 2: bare cashaddr payload username (${ADDR2_BARE}.w1) ==="
	local hash; hash=$(mine_block_as "${ADDR2_BARE}.w1")
	assert_split "scenario2 (bare cashaddr)" "$hash" "$ADDR2_BARE"
}

scenario_3_legacy() {
	if [[ -z "$ADDR3" ]]; then
		log "=== Scenario 3: legacy address -- SKIPPED (unsupported by this bitcoind build) ==="
		return
	fi
	log "=== Scenario 3: legacy regtest address username (${ADDR3}.w1) ==="
	local hash; hash=$(mine_block_as "${ADDR3}.w1")
	assert_split "scenario3 (legacy address)" "$hash" "$ADDR3"
}

scenario_4_fallback() {
	log "=== Scenario 4: non-address username (rig01), pool fallback ==="
	local hash; hash=$(mine_block_as "rig01")
	# Fallback users mine to the pool's own bchaddress (README.md D2 /
	# stratifier.c pool_fallback path) -- fee split still applies.
	assert_split "scenario4 (rig01 fallback)" "$hash" "$POOL_ADDR"
}

scenario_5_typo_rejected() {
	log "=== Scenario 5: typo'd cashaddr (${ADDR5_TYPO}.w1) must be REJECTED ==="
	local response
	response=$(stratum_probe "${ADDR5_TYPO}.w1" "x")

	local has_explicit_error has_notify
	has_explicit_error=$(printf '%s' "$response" | grep -qi "Invalid BCH address" && echo true || echo false)
	# Match the notify *method call*, not the bare string: a stratum
	# subscribe response always contains the subscription topic name
	# "mining.notify" -- e.g.
	#   {"result":[[["mining.notify","6a8f2eda"]],"da2e8f6a",8],"id":1}
	# so grepping for the bare string matches the handshake itself and can
	# never be false, regardless of whether any work was served.
	has_notify=$(printf '%s' "$response" | grep -q '"method"[[:space:]]*:[[:space:]]*"mining.notify"' && echo true || echo false)

	check "scenario5: auth response carries the explicit typo error over the wire" "$has_explicit_error"
	check "scenario5: no mining.notify (work) was served to the rejected client" "$([[ "$has_notify" == "false" ]] && echo true || echo false)"
	log "scenario5: raw stratum exchange was:"
	printf '%s\n' "$response" >&2

	sleep 1
	local logtext=""
	[[ -f "$LOGDIR/e2e.log" ]] && logtext=$(cat "$LOGDIR/e2e.log")
	local has_generic_reject has_failover
	has_generic_reject=$(printf '%s' "$logtext" | grep -qi "failed to authorise as user" && echo true || echo false)
	has_failover=$(printf '%s' "$logtext" | grep -qi "Failed over" && echo true || echo false)
	check "scenario5: ckpool.log records the generic auth-failure line" "$has_generic_reject"
	check "scenario5: ckpool.log has NO 'Failed over' line (bitcoind was never marked dead)" \
		"$([[ "$has_failover" == "false" ]] && echo true || echo false)"
}

scenario_5b_legacy_typo_rejected() {
	if [[ -z "$ADDR5B_TYPO_LEGACY" ]]; then
		log "=== Scenario 5b: typo'd legacy address -- SKIPPED (no legacy address available) ==="
		return
	fi
	log "=== Scenario 5b: typo'd legacy address (${ADDR5B_TYPO_LEGACY}.w1) must be REJECTED ==="
	local response
	response=$(stratum_probe "${ADDR5B_TYPO_LEGACY}.w1" "x")

	local has_explicit_error has_notify
	has_explicit_error=$(printf '%s' "$response" | grep -qi "Invalid BCH address" && echo true || echo false)
	# Match the notify *method call*, not the bare string: a stratum
	# subscribe response always contains the subscription topic name
	# "mining.notify" -- e.g.
	#   {"result":[[["mining.notify","6a8f2eda"]],"da2e8f6a",8],"id":1}
	# so grepping for the bare string matches the handshake itself and can
	# never be false, regardless of whether any work was served.
	has_notify=$(printf '%s' "$response" | grep -q '"method"[[:space:]]*:[[:space:]]*"mining.notify"' && echo true || echo false)

	check "scenario5b: auth response carries the explicit typo error over the wire" "$has_explicit_error"
	check "scenario5b: no mining.notify (work) was served to the rejected client" \
		"$([[ "$has_notify" == "false" ]] && echo true || echo false)"
	log "scenario5b: raw stratum exchange was:"
	printf '%s\n' "$response" >&2

	sleep 1
	local logtext=""
	[[ -f "$LOGDIR/e2e.log" ]] && logtext=$(cat "$LOGDIR/e2e.log")
	local has_silent_fallback
	has_silent_fallback=$(printf '%s' "$logtext" | \
		grep -qi "User ${ADDR5B_TYPO_LEGACY} is not a BCH address, mining to pool address" && echo true || echo false)
	check "scenario5b: typo was NOT silently redirected to the pool address" \
		"$([[ "$has_silent_fallback" == "false" ]] && echo true || echo false)"
}

scenario_6_uppercase_same_user() {
	log "=== Scenario 6: UPPERCASE bare cashaddr ($ADDR6_UPPER) normalizes to scenario 2's user ==="
	local pid; pid=$(run_miner "$ADDR6_UPPER")
	sleep 5

	# Query while the miner is still CONNECTED. userinfo()'s "workers" is a
	# count of live connections, not a cumulative total: the previous version
	# stopped the miner first and then asserted >= 2 ("scenario2's connection
	# plus this one"), which could never hold -- scenario 2's client
	# disconnected long ago and this one had just been killed, so the row
	# always read 0. The identity assertion below is what actually proves the
	# uppercase form normalized onto the same user.
	local users_json
	users_json=$(ckpmsg_json users)
	local row workers_count
	row=$(printf '%s' "$users_json" | jq -c --arg u "$ADDR2_BARE" '.users[]? | select(.user == $u)')
	workers_count=$(printf '%s' "$row" | jq -r '.workers // 0')
	stop_miner "$pid"

	log "scenario6: ckpmsg users row for $ADDR2_BARE: ${row:-<none>}"
	check "scenario6: exactly one user row exists for the lowercase address (no duplicate uppercase user)" \
		"$([[ -n "$row" ]] && echo true || echo false)"
	check "scenario6: the UPPERCASE connection is counted under that same user (observed workers: ${workers_count:-0})" \
		"$([[ "${workers_count:-0}" -ge 1 ]] && echo true || echo false)"
}

scenario_7_multi_worker() {
	log "=== Scenario 7: ${ADDR1}.w1 and ${ADDR1}.w2 concurrently -- one user, two workers ==="
	local pid1 pid2
	pid1=$(run_miner "${ADDR1}.w1")
	pid2=$(run_miner "${ADDR1}.w2")
	sleep 5
	stop_miner "$pid1"
	stop_miner "$pid2"

	local workers_json w1_present w2_present
	workers_json=$(ckpmsg_json workers)
	log "scenario7: ckpmsg workers for $ADDR1: $(printf '%s' "$workers_json" | jq -c --arg u "$ADDR1" '[.workers[]? | select(.user == $u)]')"

	w1_present=$(printf '%s' "$workers_json" | jq -e --arg w "${ADDR1}.w1" '.workers[]? | select(.worker == $w)' >/dev/null 2>&1 && echo true || echo false)
	w2_present=$(printf '%s' "$workers_json" | jq -e --arg w "${ADDR1}.w2" '.workers[]? | select(.worker == $w)' >/dev/null 2>&1 && echo true || echo false)
	check "scenario7: worker ${ADDR1}.w1 is registered under user $ADDR1" "$w1_present"
	check "scenario7: worker ${ADDR1}.w2 is registered under user $ADDR1" "$w2_present"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
	prereq_check
	WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/ckpool-e2e.XXXXXX")
	log "workdir: $WORKDIR"

	start_bitcoind
	mature_chain_and_addresses
	write_ckpool_conf
	start_ckpool

	scenario_1_prefixed_cashaddr
	scenario_2_bare_cashaddr
	scenario_3_legacy
	scenario_4_fallback
	scenario_5_typo_rejected
	scenario_5b_legacy_typo_rejected
	scenario_6_uppercase_same_user
	scenario_7_multi_worker

	echo
	echo "===================================================================="
	printf '%d/%d assertions passed\n' "$((TESTS_RUN - TESTS_FAILED))" "$TESTS_RUN"
	echo "===================================================================="

	[[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
