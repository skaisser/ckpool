# Phase 9 — Regtest end-to-end money gate: results

**Status: DEFERRED — no BCH node or Linux build environment on the authoring
machine (macOS, no Docker).**

`testing/regtest-e2e.sh` is written, syntax-checked, and shellcheck-clean, but
it has **not been executed** as part of this phase. Two hard blockers on the
authoring machine, both confirmed by direct attempt (not assumed):

1. `src/libckpool.c` `#include <sys/epoll.h>` directly (line 19) and calls
   `epoll_create1`/`epoll_ctl`/`epoll_wait` (lines 1007-1096) — this header
   does not exist on macOS/BSD. `src/ckpool`, `src/ckpmsg`, and the
   `test/addrclassify` binary (which links the real `src/libckpool.c`) cannot
   be compiled here regardless of any other dependency being satisfied.
2. No `bitcoind`/`bitcoin-cli` (BCHN) and no Docker are installed on this
   machine, so even a hypothetically-compiled `ckpool` binary would have no
   regtest node to talk to.

`testing/minerd` is confirmed to be a pre-compiled 64-bit Linux ELF binary
(`file` output: `ELF 64-bit LSB executable, x86-64, ... for GNU/Linux
2.6.26 ... stripped`) — another reason this script can only execute on the
Ubuntu pool server, matching `testing/README.md`'s existing note that it's a
Linux-only binary.

## Run this on the Ubuntu pool server

```bash
# 1. Build (from repo root)
./autogen.sh
./configure
make

# 2. Confirm prerequisites the script checks for itself
which bitcoind bitcoin-cli jq          # BCHN + jq must be in PATH
test -x src/ckpool && test -x src/ckpmsg && test -x testing/minerd

# 3. Run the money gate
./testing/regtest-e2e.sh
```

Exit code `0` = every assertion passed. `2` = a prerequisite was missing
(nothing was started — see the printed list). `1` = the pool started but at
least one scenario FAILed; the script preserves its `$TMPDIR/ckpool-e2e.*`
workdir (bitcoind datadir, ckpool conf, ckpool log, per-scenario minerd logs)
on failure instead of deleting it, and tails the last 40 lines of
`logs/e2e.log` to stderr.

Paste the full stdout/stderr of that run into "Server run results" below —
every `check()` call in the script prints `PASS:`/`FAIL:` with the observed
and expected values inline, so the transcript is self-contained evidence;
no manual `getblock` transcription needed.

## Scenario / assertion matrix implemented by the script

| # | Username | Mechanism | Expected outcome | Assertions made |
|---|---|---|---|---|
| 1 | `<prefixed cashaddr>.w1` | `minerd`, mine to a found block | authorized, direct payout | coinbase has 2 outputs; vout[0] = 98% (truncated) to the address; vout[1] = 2% remainder to `pooladdress`; sum of outputs = coinbasevalue |
| 2 | `<bare cashaddr payload>.w1` | `minerd`, mine to a found block | identical to #1, no prefix | same 5 assertions as #1 |
| 3 | `<legacy regtest address>.w1` | `minerd`, mine to a found block (skipped if this bitcoind build has no `getnewaddress ... legacy`) | identical to #1, legacy format | same 5 assertions as #1, or explicit SKIP note |
| 4 | `rig01` | `minerd`, mine to a found block | authorized as pool-fallback | same 5 assertions as #1 but expected miner-side payee is the pool's own `bchaddress`, not a miner-owned key |
| 5 | `<prefixed cashaddr with last char flipped>.w1` | raw stratum JSON-RPC probe (`mining.subscribe` + `mining.authorize` over `/dev/tcp`) | REJECTED at auth | wire-level response contains the exact string "Invalid BCH address..."; no `mining.notify` (no work) was ever sent; `logs/e2e.log` contains the generic "failed to authorise as user" line; `logs/e2e.log` contains **no** "Failed over" line |
| 6 | `<bare cashaddr payload from #2, uppercased>` | `minerd`, connect only (no block wait) | authorized, same user row as #2 (lowercase) | `ckpmsg … users` shows exactly one row for the lowercased address with `workers >= 2` (proves no duplicate user was created for the uppercase form) |
| 7 | `<prefixed cashaddr from #1>.w1` + `.w2` concurrently | two `minerd` instances in parallel | one user, two worker rows | `ckpmsg … workers` lists both `<addr>.w1` and `<addr>.w2` under the same user |

Every `check()` call prints the scenario name, a human description of what
was asserted, and the observed value(s) — e.g.
`PASS: scenario1 (prefixed cashaddr): vout[0] is 98% of coinbasevalue
truncated down (observed 49009999999900, expected 49009999999900)` — so a
pasted transcript is directly pasteable evidence, matching the Acceptance
section's requirement for pasted `getblock` coinbase decodes.

### Known limitation in the script's assertions (flagged)

`assert_split()` derives `total` from the block's own two coinbase outputs, so
its "outputs sum to coinbasevalue" check is self-referential (always true as
written); the 98/2 ratio checks against that total are the real assertions,
and the fee-truncation direction (fee truncates down, miner absorbs the
remainder) is asserted correctly. A future improvement would compare `total`
against an independently-fetched expected value (subsidy + block fees via
`getblockstats`).

### Known deviation from the phase's literal wording (flagged, not silently made)

The phase description says to "grep ckpool log for the explicit error" for
scenario 5. Reading `stratifier.c` shows this is not actually possible: the
explicit `"Invalid BCH address (bad checksum or wrong network) - check your
username for typos"` string (stratifier.c:5750) is only ever placed in the
JSON `error` field of the stratum `mining.authorize` response and in a
`client.show_message` push (`send_auth_failure`, stratifier.c:7245-7248) —
it is sent to the client over the wire, never written to `logs/e2e.log`.
`LOGDEBUG("Sending stratum message %s", stratum_msgs[msg_type])`
(stratifier.c:3548) only logs the message *type* name (e.g. `authresult`),
not its JSON body. The script therefore captures the explicit error text
with a raw stratum probe against the live TCP port instead of a log grep,
and separately confirms via log grep that (a) the generic "failed to
authorise as user" line is present and (b) no "Failed over" line appears —
which the plan's own Acceptance section requires and which genuinely does
land in the log.

## Local verification already performed (without a BCH node, on macOS)

These are the checks that do **not** require a running pool or a BCH node —
static/pure-function correctness — and were re-run live during this phase
(not just carried forward as a claim) wherever the code path doesn't touch
`<sys/epoll.h>`:

| Suite | What it tests | Result | Re-verified in this phase? |
|---|---|---|---|
| `test/cashaddr.c` (Phase 1) | `cashaddr_simple.c` checksum/prefix/case handling: valid mainnet P2PKH+P2SH (prefixed/prefixless/uppercase), production addresses, single-character-typo rejection (payload and last-char), mixed-case rejection, wrong-network-prefix rejection, unknown-prefix rejection, truncated payload, invalid-charset chars (`b`/`i`/`o`/`1`) | **34/34 passed** | **Yes** — compiled standalone (`gcc -I src -I <jansson prefix>/include test/cashaddr.c src/cashaddr_simple.c`, no epoll dependency in this compilation unit) and executed on this machine just now. Full pass list is reproducible; see command above. |
| `test/addrclassify.c` (Phase 2) | `bch_classify_address()`/`bch_address_to_script()`/`address_to_txn()` in `src/libckpool.c` agreeing on prefixed/bare/uppercase cashaddr, legacy Base58Check, testnet-vs-mainnet prefix switching, garbage/edge cases, production addresses | **70/70 passed** | **Yes** — the orchestrating session compiled and ran it natively on macOS (twice: after Phase 2 and again after the Phase 7 cleanup) using a stub-header harness (scratchpad `stubinc/` provides a minimal `config.h`, `sys/epoll.h`, `sys/prctl.h` and glibc shims), linking the real `src/libckpool.c` + `src/cashaddr_simple.c` + `src/sha2.c`. The server run's `cd test && make check` remains the authoritative Linux re-proof. |
| `looks_like_address()` (Phase 4, `stratifier.c:5396`, static/unexported) | Known-prefix, bare-42-char-cashaddr-shape, legacy-shape (`1`/`3` start, base58 charset, len 25-36) detection vs. plain usernames | **16/16 passed** | **Yes** — this is a small `static` pure function with no I/O; its body was copied verbatim into a throwaway `/tmp` scratch harness (16 cases: 10 must-look-like-address incl. all three prefixes/case/both shape families/both length boundaries, 6 must-not incl. NULL/empty/plain names/off-by-one-short/wrong-leading-char) and run on this machine. All 16 passed. The harness is not part of the repo (scratch-only, per Phase 9's Touches scope) but is reproducible from the function body cited above. |
| Per-file syntax gates | `gcc -fsyntax-only` / clean compile of touched files | Partial | `src/cashaddr_simple.c` + `src/cashaddr_simple.h` compile warning-free standalone (proven above, since `test/cashaddr.c` links it directly). `src/bitcoin.c`, `src/libckpool.c`, `src/generator.c`, `src/stratifier.c`, `src/ckpool.c` all transitively require `config.h` (autoconf-generated, needs `./configure`) **and** `<sys/epoll.h>` — neither is available/buildable on macOS, so these five files' "build clean, no new warnings" acceptance criterion can only be checked on the Ubuntu server (`make` output). |

## Server run results

_(to be filled in after `./testing/regtest-e2e.sh` runs on the Ubuntu pool
server — paste full stdout/stderr here, plus `cd test && make check` output
for the `test/addrclassify.c` 70/70 re-confirmation.)_

```
<paste here>
```
