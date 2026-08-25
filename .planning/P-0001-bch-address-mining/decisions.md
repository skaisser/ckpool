# Closed decisions — P-0001 bch-address-mining

Locked via operator interview, 2026-08-25. Do not reopen without operator sign-off.

## D1 — Deployment: full cutover to solo mode
Production runs one instance with `-B` (btcsolo). Per-address usernames are paid
directly on-chain with the fee split; non-address usernames fall back to mining
for the pool address (economically identical to today's pooled behavior), so no
existing miner is lost. No second instance / port.

## D2 — Invalid-username policy: smart fallback
- Username that **looks like an attempted address** — starts with `bitcoincash:`,
  `bchtest:`, `bchreg:`, `q`/`p` payload shape, or legacy `1`/`3` shape — but fails
  checksum/validation → **REJECT auth** with a clear error string, so the miner
  notices the typo instead of silently mining for the pool.
- Any other username (`skaisser`, `rig01`, …) → **authorize** and mine to the
  pool's `btcaddress` (fee split irrelevant: pool pays itself).
- Wrong-network prefix on mainnet (`bchtest:`/`bchreg:`) counts as
  looks-like-address → reject.

## D3 — Pool fee: 2.0%
Production `poolfee` is 2.0 (`pooladdress` receives 2%, miner 98%). Acceptance
gates assert a 98/2 coinbase split. Split math stays configurable (0–100).

## D4 — BCH-only: no Bitcoin-mining compatibility retained
(Locked by operator, 2026-08-25.) EloPool targets Bitcoin Cash exclusively.
No BTC-oriented code path is preserved for compatibility: segwit/bech32
address handling, witness-commitment coinbase insertion, and hardcoded BTC
donation addresses are removed or made unreachable-and-asserted. Upstream
ports are filtered to BCH-relevant fixes only (BIP54/segwit/SV2 excluded).

## Engineering decisions closed by recon (facts, not preferences)
- CashAddr checksum MUST be verified (polymod is currently dead code) — typo'd
  addresses must never decode to a payable script.
- Prefixless cashaddr (`qq…`) must be detected and routed through the cashaddr
  decoder — never base58 — in BOTH validate_address and address_to_txn.
- Legacy address validation moves to local base58check (sha256d checksum), so
  auth classification never depends on live RPC (transient node outage must not
  reclassify a valid-address miner into pool-fallback).
- generator_checkaddr must stop marking the bitcoind node dead on a merely
  invalid address (today any bad username triggers node failover).
