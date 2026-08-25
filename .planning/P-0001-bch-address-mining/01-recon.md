# Recon evidence — P-0001 bch-address-mining

Consolidated from lead-session certified reads plus three recon agents (auth flow,
rental compat, upstream drift) on 2026-08-25. All line numbers verified against
working tree at commit 11692101.

## Architecture facts

- generator/stratifier/connector are **pthreads in one process** (ckpool.c:1543-1551);
  `generator_checkaddr` is a direct in-thread call from the stratifier borrowing the
  generator's connsock — no IPC queue involved.
- Username split: `strsep(&base_username, "._")` (stratifier.c:5432) — splits on `.`
  AND `_`. CashAddr payload charset and `bitcoincash:` prefix contain neither, legacy
  Base58 contains neither → `address.worker` and `address_worker` both yield the right
  user part. `:` is allowed (only `/` is rejected, stratifier.c:5575) and is a legal
  ext4 filename byte for `logs/users/<username>`.
- Address detection already runs for every new user in every non-proxy mode
  (stratifier.c:5451-5457): `generator_checkaddr()` → `user->btcaddress = true` +
  `user->txnlen = address_to_txn(...)`. Address-as-username is the native design.
- Solo mode (`-B`): per-user coinbase via `__generate_userwb` (stratifier.c:1016-1039)
  = shared coinb2 + user output + **coinb3 (pool-fee output) appended** — the 98/2
  split composes with per-user payout. Fee math at stratifier.c:604-651: `d64 =
  coinbasevalue * poolfee / 100` (double → truncating int), miner gets
  `coinbasevalue - d64`, integers always sum to coinbasevalue.
- Non-solo mode ignores `user->btcaddress` entirely; coinbase always pays
  `ckp->btcaddress` (stratifier.c:667-675, banner at :709).

## Defects / gaps blocking the feature (all verified in code)

### D-A: CashAddr checksum never verified — CRITICAL, money-loss
`cashaddr_decode_simple` (cashaddr_simple.c:79-166) strips the last 8 chars and
decodes the rest; `polymod()` (:30) is dead code. Any typo'd address with valid
charset/length decodes to a wrong hash160 → block reward paid to an unspendable
script. Also accepts mixed case (spec forbids) via tolower().

### D-B: Prefixless cashaddr routed to Base58 — CRITICAL, money-loss
`validate_address` (bitcoin.c:49-63) and `address_to_txn` (libckpool.c:1826-1831)
take the cashaddr path only when a `bitcoincash:`/`bchtest:`/`bchreg:` prefix is
present. A bare `qq…` username goes to bitcoind `validateaddress` (BCHN accepts
prefixless → isvalid true) and is then decoded as **base58** by
`address_to_pubkeytxn` (libckpool.c:1781) → garbage hash160 in the coinbase.
Validation and script-construction can disagree — the worst class of bug here.

### D-C: Invalid address marks bitcoind dead — failover flap / DoS
`generator_checkaddr` (generator.c:960-968) treats any false return from
`validate_address` — including a merely invalid username — as node failure:
`si->alive = false` + `reconnect_generator()`. One typo'd login flaps failover.
Invalid non-cashaddr usernames also re-hit the RPC on **every** auth retry
(cache at stratifier.c:5451 only caches success).

### D-D: No fallback for invalid usernames in solo mode — the feature gap
stratifier.c:5666: `if (!ckp->btcsolo || client->user_instance->btcaddress) ret =
true;` — sole authorization gate. Invalid ⇒ reject, backoff doubling
(:5518-5521), `client->reject = 3` (:5522) ⇒ connection dropped (:7570-7574).
No pool-address fallback exists anywhere (exhaustive flag search: none).
⚠️ The `out_nouserwb` branch of `__user_coinb2` (stratifier.c:5969-5971) is NOT a
usable hook: in solo mode `wb->coinb2bin` carries the output-count byte (2) and
the miner value but NO output scripts (they live in per-user userwbs/coinb3) —
serving it produces a malformed coinbase. The fallback must instead populate the
user's `txnbin/txnlen` from the pool's `sdata->txnbin` and build a normal userwb
(extending the `!instance->btcaddress` skip at :1047 accordingly), and the
malformed `out_nouserwb` branch needs a defensive fix of its own.

### D-E: pool.status NULL-fp crash
stratifier.c:8291-8306: failed fopen is logged, then `fprintf(fp, …)` runs
unconditionally → stratifier crash on disk-full/permission error. Upstream fix
130c755 (see 02-upstream-patches.md).

### D-F: workbase_id off-by-one (upstream a439cf9)
`next_blockid = sdata->workbase_id + 1` (stratifier.c:5761) and
`diff_change_job_id = workbase_id + 1` (:6634) — diff changes take effect one
job late; shares judged against the wrong diff window.

### D-I: poolfee unclamped; no dust/zero guard on fee output
`poolfee` is read raw (ckpool.c:1451-1452, no clamp — unlike `donation`, clamped
[0.1,99.9] at :1497-1500). `poolfee > 100` underflows `g64 -= d64`
(stratifier.c:610) → ~1.8e19-sat output (startup checktxn would likely catch it
and exit, but it's a loud-crash config footgun). No guard against `d64` being 0
or below the 546-sat dust limit (invalid/nonstandard block). JSON integer
`"poolfee": 2` (no decimal) may parse as 0 — README warns "must include decimal".

### D-J: decoder is network/prefix-blind; solo without btcaddress adopts a BTC address
`cashaddr_decode_simple` locates the prefix (cashaddr_simple.c:85-92) but never
compares it to the expected network nor feeds it into any checksum — any prefix
(`dogecoin:qre…`) decodes; a `bchtest:` address passes the callers' prefix list
and is silently used on mainnet. Separately, generator.c:256-267 falls back to
hardcoded **BTC** donation addresses (bech32, ckpool.c:1771-1776) as
`ckp->btcaddress` when btcsolo is set with no btcaddress configured — on BCH the
pool's fallback address must never be a BTC address; solo + fallback must hard-
require a valid configured btcaddress.

### D-K: cashaddr_to_script 0-return unchecked
`cashaddr_to_script` returns 0 on decode failure (cashaddr_simple.c:196-198) and
no caller checks it (stratifier.c:5455, 8754, 8762) → zero-length output script.
Guard all three call sites.

### D-G: uppercase cashaddr creates a duplicate user
`get_create_user` uses case-sensitive `HASH_FIND_STR` (stratifier.c:5340,5352).
`BITCOINCASH:QQ…` registers as a distinct user from the lowercase form.
Normalize cashaddr usernames to lowercase at ingest.

### D-H: mindiff_overrides can clobber rental diff (narrow)
Pattern loop (stratifier.c:5589-5606) substring-matches the FULL username and
runs AFTER subscribe-time NiceHash/MRR detection with no guard. Multi-char keys
containing any of `b i o 1` cannot collide with cashaddr payloads; 1–2 char keys
(`s9`, `l7`) match ~4% of addresses and would override a rental's 500k/1M diff.
Fix: skip the loop when useragent already matched a rental service.

## Confirmed SAFE (no change needed)

- NiceHash/MRR useragent detection (stratifier.c:4995-5041) runs at subscribe,
  before any username exists — structurally username-independent. Exact-key
  lookup into mindiff_overrides, defaults 500k/1M.
- Password `d=`/`diff=` parsing (stratifier.c:5609-5641) reads params[1] only;
  overrides pattern diff — correct precedence for rentals.
- Subscribe/extranonce path has zero username dependency.
- Fee split in solo mode already works (see __generate_userwb above); verified on
  testnet blocks 1677558/1677572 per README.
- Legacy Base58 addresses: validated via bitcoind RPC (works), decoded by
  b58tobin (works when validation passed). Phase work moves validation local
  (base58check sha256d) to remove the live-RPC dependency at auth.

## Upstream drift (recon-upstream, verified locally)

Fork base: ckpool-solo `solobtc` 60768aeb (2025-07-08); upstream master now
c26eb7ff (2026-08-20), 218 commits ahead, has absorbed solo mode and moved to
yyjson + SV2 (future cherry-picks will only get harder).

- **No upstream payout/coinbase-value or auth/address-validation fixes since the
  fork** — the money math has no known upstream bugs.
- Port now (small, jansson-compatible, verified missing): a439cf9 (D-F),
  130c755 (D-E), 66db3aa (burst vardiff — rental bursts retarget in ~1min),
  3a6da1f (accept MIN(diff, old_diff) — partly neutralized by this fork's
  "accept ≥ mindiff" policy; port for correctness of share accounting).
- Later/optional: submit-error standardization (0bd3d75/c1314c6, a3b9fcb,
  0631bd7), dropped-client bookkeeping (bc6c916/0554020), shutdown deadlock
  (e22720e).
- Noted, not urgent: process_block uses fixed 1024-byte coinbase hex buffers
  (stratifier.c:2068,2074) → 511-byte binary coinbase cap; current dual-output
  P2PKH coinbase ≈200 bytes. Add a defensive length check.
- Not applicable: BIP54 prep (BTC-only), yyjson migration, SV2, remote/node/
  passthrough overflow series.

Diffs of the four port-now commits: [02-upstream-patches.md](02-upstream-patches.md).
