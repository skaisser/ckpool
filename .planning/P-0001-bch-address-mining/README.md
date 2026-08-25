---
id: P-0001
title: Per-address solo mining with 2% fee split and smart fallback
type: feat
repo: ckpool
created: 2026-08-25
---

# Per-address solo mining with 2% fee split and smart fallback

> **Type:** execution scope — reviewed, ready for `/orchestrate`.

Cut EloPool (BCH ckpool fork) over to solo mode (`-B`): miners set their BCH
address — CashAddr with/without prefix, or legacy Base58 — as the stratum
username (`address.worker` / `address_worker` for multiple workers, solopool.org
style), the block reward pays them directly on-chain with 2% to `pooladdress`,
and non-address usernames fall back to mining for the pool's `btcaddress`.
The per-address machinery already exists (`__generate_userwb`, fee output
`coinb3` composes with it); what recon found instead is four money-losing or
availability defects that MUST land before real funds ride on this, plus the
missing fallback. Read order: this file → [decisions.md](decisions.md) →
[01-recon.md](01-recon.md) (defects D-A…D-K, all file:line-verified) →
[02-upstream-patches.md](02-upstream-patches.md).

Real money: every phase that touches payout code carries its own regtest or
unit verification, and Phase 9 is a full end-to-end money gate on regtest.
Per decision D4 the pool is BCH-only: no Bitcoin-mining compatibility is
kept, and Phase 7 strips the remaining BTC leftovers.

## What is canonical and NOT changing

- Stratum wire protocol, subscribe/extranonce handling, session reconnect.
- Username split convention: `strsep(…, "._")` — first `.` or `_` ends the
  address part (stratifier.c:5432). `address.worker` multi-worker stays as-is.
- Fee-split arithmetic: fee truncates down, miner absorbs the remainder,
  outputs always sum exactly to `coinbasevalue` (stratifier.c:604-624).
- NiceHash/MRR useragent detection at subscribe time and password
  `d=`/`diff=` precedence over pattern diff (verified username-independent).
- Multi-node failover design (generator.c) — only the invalid-address
  dead-marking bug inside `generator_checkaddr` changes.
- Historical blocks/payouts (66 mainnet blocks to the pool's legacy address)
  — nothing retroactive.

## Closed decisions

See [decisions.md](decisions.md). Summary — do not reopen:
- **D1**: full cutover, one instance with `-B`; fallback keeps non-address
  users mining for the pool, so nobody is lost.
- **D2**: smart fallback — usernames that *look like* an attempted address
  (any known prefix, bare-cashaddr shape, legacy `1`/`3` shape) but fail
  validation are REJECTED with a clear error; anything else authorizes and
  mines to the pool's `btcaddress`. Wrong-network prefix ⇒ reject.
- **D3**: production `poolfee` = 2.0; acceptance asserts a 98/2 split; the
  percentage stays configurable.

## Traps

- **Validation and script-construction must never disagree.** Today
  `validate_address` (bitcoin.c) and `address_to_txn` (libckpool.c) classify
  independently — that's how D-B (bare cashaddr → base58 garbage) happens.
  Phase 2 must give both the SAME classifier; fixing only one reintroduces the
  bug. Threatens Phases 2 and 4.
- **`out_nouserwb` is a malformed-coinbase branch in solo mode** (output-count
  byte 2, no scripts — stratifier.c:5969-5971). Do NOT route fallback users
  through it; build them a real userwb from the pool script. Threatens Phase 4.
- **Do not break prefixed config addresses.** Production `btcaddress` /
  `pooladdress` are prefixed CashAddr and validate through the same code being
  changed; startup (stratifier.c:8747-8768) must keep succeeding. Threatens
  Phases 1-2.
- **The auth path must stay RPC-free after Phase 2.** A transient bitcoind
  outage at authorize time must never reclassify a valid-address miner into
  pool-fallback (that would silently redirect their block to the pool).
  Threatens Phase 4 — verify no `generator_checkaddr` call remains on the
  miner-username path, or that it no longer performs RPC for it.
- **Checksum spec detail:** CashAddr checksum input includes the expanded
  prefix (low 5 bits of each char + zero separator); a prefixless input must
  be checksummed against the network's expected prefix, not against nothing.
  Getting this wrong rejects every valid address. Threatens Phase 1.
- **generator.c:256 BTC-donation fallback**: with `-B` and no `btcaddress`,
  the pool adopts a hardcoded BTC bech32 address. Smart fallback requires a
  valid BCH `btcaddress` — make its absence a fatal startup error in solo
  mode. Threatens Phase 4.
- **Rental diff clobber**: mindiff_overrides pattern loop runs after
  useragent detection with no guard; 1-2 char keys substring-match ~4% of
  addresses. Phase 8 adds the guard; until then keep every override key ≥3
  chars or containing one of `b i o 1`.

## Phases

### Phase 0: Re-verify recon premises (read-only) [S]

**Touches:** (read-only — no files modified)

- [ ] Confirm at current HEAD: `polymod` never called in src/cashaddr_simple.c; auth gate `stratifier.c:5666`; cashaddr prefix gates in `bitcoin.c:49-63` and `libckpool.c:1826-1831`; `poolfee` unclamped in `ckpool.c:1451-1452`; `donvalid` never assigned; `generator_checkaddr` dead-marking at `generator.c:960-968`; solo `wb->coinb2bin` carries no output scripts (malformed `out_nouserwb`). Report PASS/FAIL per claim.
- [ ] If any premise fails, STOP the run and report — do not adapt silently.

**Verify:** report lists every claim with PASS + current line number.

### Phase 1: CashAddr correctness — checksum, prefix, case [S]

**Touches:** `src/cashaddr_simple.c`, `src/cashaddr_simple.h`, `test/Makefile.am`, `test/cashaddr.c` (new)

- [ ] Implement full CashAddr checksum verification in `cashaddr_decode_simple` using the existing `polymod` (prefix-expansion per spec: low 5 bits of each prefix char, zero separator, payload symbols; valid iff polymod == 0 after the spec's XOR-1 convention). Reject on mismatch.
- [ ] Enforce expected network prefix: new API takes the expected prefix (`bitcoincash`/`bchtest`/`bchreg`); prefixed input must match it, prefixless input is checksummed against it. Wrong network ⇒ reject.
- [ ] Reject mixed-case input (all-lower or all-upper only); keep accepting all-upper by lowercasing after the check.
- [ ] Fix version-byte handling: mask type with `0x0f`, require reserved high bit zero.
- [ ] Make `cashaddr_to_script` failures detectable and check the return at all call sites (`stratifier.c:5455`, `:8754`, `:8762` — via the Phase 2 wrapper if cleaner).
- [ ] Write `test/cashaddr.c`: spec test vectors (valid mainnet P2PKH+P2SH, prefixless, uppercase), negative vectors (single-char typo, wrong prefix, mixed case, bad padding, truncated), wire into `test/Makefile.am`.

**Verify:** `cd test && make check` (or direct build+run of the new test binary) — all vectors pass; a one-character typo of a valid address is rejected.

### Phase 2: One address classifier for validation AND script construction [S]

**Touches:** `src/bitcoin.c`, `src/libckpool.c`, `src/libckpool.h`

- [ ] Add a single classification function (e.g. `bch_parse_address(addr, expected_prefix, out_script, out_len, out_is_p2sh)`) that handles: prefixed CashAddr, bare CashAddr (charset shape + checksum against expected prefix), legacy Base58Check verified LOCALLY (double-SHA256 checksum + version byte 0x00/0x05 mainnet, 0x6f/0xc4 testnet/regtest). No RPC anywhere in it.
- [ ] Rewrite `validate_address` (bitcoin.c) for BCH inputs as a thin wrapper over the classifier; keep the bitcoind `validateaddress` RPC only as a last-resort path that can never be reached by CashAddr or legacy-shaped input.
- [ ] Rewrite `address_to_txn` (libckpool.c:1824) over the same classifier so the script is built from the same decode that validated; return 0 only on failure and never silently base58-decode a cashaddr.
- [ ] Determine network at runtime from existing config/chain state (find the fork's testnet/regtest signal — GBT/chain detection or config flag) and pass the right expected prefix.

**Verify:** targeted C test or scratch harness: for each of {prefixed cashaddr, bare cashaddr, uppercase cashaddr, legacy 1…, legacy 3…, typo'd variants, `bchtest:` on mainnet}: validate_address and address_to_txn agree (both accept with identical script bytes, or both reject). Paste the matrix.

### Phase 3: generator_checkaddr — invalid address ≠ dead node [S]

**Touches:** `src/generator.c`

- [ ] Split the failure semantics in `generator_checkaddr` (generator.c:945-972): only a transport/RPC failure marks `si->alive = false` and triggers failover; a definitive "address invalid" answer returns false with the node untouched.

**Verify:** code inspection plus grep: no path where a locally-rejected address reaches `si->alive = false`; build clean.

### Phase 4: Solo smart fallback, case normalization, startup guards [S]

**Touches:** `src/stratifier.c`, `src/generator.c`, `src/ckpool.c`

- [ ] In `generate_user` (stratifier.c:5422): lowercase the username when it classifies as CashAddr (prevents duplicate users from `BITCOINCASH:…`, D-G) before `get_create_user`.
- [ ] Add `looks_like_address()` per decision D2: known prefix, bare-cashaddr shape (q/p start, cashaddr charset, plausible length), or legacy shape (1/3 start, base58 charset, len 25-36).
- [ ] Auth gate (stratifier.c:5666): in solo mode — valid address ⇒ authorize (unchanged); invalid + looks-like-address ⇒ reject with explicit error string naming the reason (bad checksum / wrong network); invalid + not-address-like ⇒ authorize as **pool-fallback**: populate `user->txnbin/txnlen` from `sdata->txnbin/txnlen`, mark the user (new flag, e.g. `user->pool_fallback`), log clearly.
- [ ] Extend `generate_userwbs`' skip (stratifier.c:1047) so pool-fallback users get userwbs too; verify `__generate_userwb` composes their coinbase identically (pool script + fee output).
- [ ] Defensively fix `out_nouserwb` (stratifier.c:5969-5971): in solo mode never serve `wb->coinb2bin` raw — log and serve a properly-formed pool-script coinbase (or drop the client) instead of a scriptless template.
- [ ] Startup guards: in `-B` mode require configured, valid `btcaddress` and (when `poolfee > 0`) `pooladdress` — fatal error otherwise; delete the BTC-donation-address fallback at generator.c:256-267 (hardcoded bech32 BTC addresses must never become a BCH pool address).

**Verify:** build clean; unit-style check of `looks_like_address()` against the Phase 2 matrix inputs; grep confirms no remaining path where an unvalidated string reaches `address_to_txn` for a user.

### Phase 5: Fee-split hardening [S]

**Touches:** `src/ckpool.c`, `src/stratifier.c`

- [ ] Clamp `poolfee` at config parse to [0, 50] with a WARNING when clamped (production value 2.0; >50 is certainly a typo — prevents the >100 uint64 underflow, D-I).
- [ ] Accept both JSON integer and real for `poolfee` (`"poolfee": 2` must equal `2.0`).
- [ ] Dust guard in `generate_coinbase`: if computed `d64` < 546 sat (or 0), emit a single-output coinbase (miner takes all) and LOGWARNING once per workbase.
- [ ] Defensive length check before block submission: if hex coinbase would exceed the fixed 1024-byte buffers in `process_block` (stratifier.c:2068-2074), LOGEMERG instead of overflowing; fix the hardcoded 40-byte `memcpy` of `txnbin` at stratifier.c:2436-2437 to use the field size.

**Verify:** build clean; scratch test of the split math at poolfee ∈ {0, 0.0001, 2, 50, 99 (clamped)} with coinbasevalue 312500000 — outputs sum exactly, no underflow, dust path collapses to one output; paste table.

### Phase 6: Port upstream fixes [S]

**Touches:** `src/stratifier.c`

- [ ] Apply the four diffs from [02-upstream-patches.md](02-upstream-patches.md), adapted to this tree: a439cf9 (workbase_id off-by-one at :5761 and :6634), 130c755 (pool.status NULL-fp crash at :8291-8306), 66db3aa (1-min rolling vardiff for share bursts), 3a6da1f (accept MIN(diff, old_diff) until next update — reconcile with the fork's existing accept-≥-mindiff policy rather than blindly overwriting it).

**Verify:** build clean; diff review shows each of the four semantic changes present; existing behavior for normal-diff shares unchanged (code inspection note per patch).

### Phase 7: BCH-only cleanup — strip BTC leftovers (decision D4) [S]

**Touches:** `src/libckpool.c`, `src/libckpool.h`, `src/bitcoin.c`, `src/ckpool.c`, `src/ckpool.h`

- [ ] Remove `segaddress_to_txn`/bech32 handling and the `segwit` branch from the address path (unreachable on BCH once the Phase 2 classifier lands); drop the `segwit` flags threaded through `validate_address` → `generator_checkaddr` → `user_instance`/config where they become dead, or hardwire them false with a one-line comment if a signature is shared.
- [ ] Remove the hardcoded BTC donation addresses (ckpool.c:1771-1776) and remaining donation residue that Phase 4 didn't already delete (`donvalid`/`dontxnbin` branches in `generate_coinbase` stratifier.c:612-618, 640-647 — dead since `donvalid` is never set; confirm then delete).
- [ ] `insert_witness`: BCH GBT never returns `default_witness_commitment` — replace the machinery with an assert/log-and-ignore rather than live coinbase branches (conservative: keep the variable, make the true-branch unreachable with a LOGEMERG).
- [ ] Do NOT touch consensus/validation logic beyond these dead paths — this phase deletes unreachable BTC code, it does not restructure live BCH code.

**Verify:** build clean; grep shows no remaining `bech32`/`segaddress`/BTC `bc1q` references in src/ (excluding comments/ChangeLog); regtest smoke from Phase 9 later re-proves coinbase validity.

### Phase 8: Rental-diff guard for mindiff_overrides [S]

**Touches:** `src/stratifier.c`

- [ ] Skip the mindiff_overrides pattern loop (stratifier.c:5589-5606) when the client's diff was already set by useragent rental detection at subscribe time (NiceHash/MRR), so an address substring can never clobber a rental's difficulty. Password `d=` keeps its override precedence.

**Verify:** build clean; trace note showing order: subscribe detection → (skipped) pattern loop → password diff still wins.

### Phase 9: Regtest end-to-end money gate (verify-only) [S]

**Touches:** `testing/regtest-e2e.sh` (new), `.planning/P-0001-bch-address-mining/03-regtest-results.md` (new)

- [ ] Write `testing/regtest-e2e.sh`: BCH node in regtest + ckpool `-B` with `poolfee 2.0`, mining via `testing/minerd` (or bitcoin-cli generate against ckpool's work where simpler), asserting via `bitcoin-cli getblock <hash> 2` coinbase vout inspection.
- [ ] Scenario matrix, each recorded with observed coinbase outputs in `03-regtest-results.md`: (1) prefixed cashaddr `addr.worker1` → 2 outputs, 98/2, miner script correct; (2) bare cashaddr username → identical result; (3) legacy address username → identical; (4) `rig01` (not address-like) → authorized, both outputs pay pool-side addresses; (5) typo'd cashaddr → auth REJECTED with the explicit error, no work served; (6) uppercase cashaddr → authorized, same user row as lowercase; (7) two workers `addr.w1`+`addr.w2` → one user, two workers in `ckpmsg … workers`.
- [ ] This phase only verifies and records; any failure is reported, not fixed here.

**Verify:** `03-regtest-results.md` contains the pasted `getblock` coinbase decode for scenarios 1-4 and the rejection log line for scenario 5.

### Phase 10: Documentation and deploy notes [H]

**Touches:** `README.md`, `ckpool.conf`, `POOL_FEE.md` (new), `install-ckpool.sh`, `post-install.sh`

- [ ] README: document the solo cutover (miners use their BCH address — CashAddr with/without prefix or legacy — as username, `address.worker` for multiple workers), the smart-fallback semantics (typo-like usernames rejected, plain names mine for the pool), 2% fee, and the ≥3-char rule for `mindiff_overrides` keys.
- [ ] Create `POOL_FEE.md` (README.md:50 links it; it does not exist) or repoint the link.
- [ ] Update sample `ckpool.conf` + install/post-install scripts and systemd unit content so production runs with `-B` and `"poolfee": 2.0`.
- [ ] Deploy note in README: cutover = config change + `-B` flag + restart; existing miners with plain usernames keep working (pool-fallback), miners must switch usernames to their own address to be paid directly.

**Verify:** grep README for the four documented behaviors; `POOL_FEE.md` exists; sample conf parses as JSON.

## Acceptance

- [ ] Regtest scenario matrix (Phase 9) recorded in `03-regtest-results.md`: a block mined with a CashAddr username (prefixed AND bare) pays exactly 98% to that address and 2% to `pooladdress`; a legacy-address username does the same; a non-address username authorizes and its block pays the pool addresses — pasted `getblock` coinbase decodes as evidence.
- [ ] A typo'd (checksum-failing) address username is rejected at authorize with an explicit error and receives no work — pasted log line.
- [ ] CashAddr unit tests pass, including: one-character typo rejected, wrong-network prefix rejected, mixed-case rejected, prefixless and uppercase forms accepted — `make check` output pasted.
- [ ] `validate_address` and `address_to_txn` provably agree on the Phase 2 matrix (no input accepted by one and mis-decoded by the other).
- [ ] An invalid username no longer marks bitcoind dead or triggers failover — log evidence from the regtest run (scenario 5 shows no "Failed over" line).
- [ ] NiceHash-style client (useragent `NiceHashMiner`) with an address username gets 500k diff from useragent detection, unaffected by the pattern loop — log evidence.
- [ ] `poolfee` clamp and dust guard behave per the Phase 5 table (outputs always sum to coinbasevalue; no underflow at any tested value).
- [ ] All four upstream ports present and the tree builds clean with no new warnings in touched files.
- [ ] BCH-only (D4): no `bech32`/`segaddress`/`bc1q` references remain in src/ code paths (grep evidence), and no BTC donation address can ever become the pool's mining or fee address.
