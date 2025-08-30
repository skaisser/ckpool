# PRD: Lean Blocks Mode for CKPool Fork

## Goal

Enable **Lean Blocks Mode** in your CKPool fork, giving your pool the option to mine “lean” blocks (coinbase-only or pruned transaction sets) to reduce propagation delay and compete with fast block finders. This must be configurable and backward-compatible so CKPool can still mine full blocks normally.

---

## Use Cases

1. **High rented hashrate bursts (≥50–100 PH):** When renting hashpower, speed of propagation is critical. Lean blocks cut propagation time and reduce stale risk.
2. **Normal solo mining with your baseline hashrate:** Generally safe to keep lean blocks **off** (or in conservative mode) to maximize fee income from full mempool inclusion.
3. **Volatile network conditions:** When block intervals are short, or mempool is thin, lean blocks can give a propagation edge.

---

## Config Changes

Add new config flags in `ckpool.conf`:

```json
"lean_blocks": true,            // Master toggle (default: false)
"lean_mode": "coinbase-only",   // Options: "off", "coinbase-only", "top-n", "size-cap"
"lean_maxtx": 10,               // If mode == top-n, number of tx to keep
"lean_maxkb": 50,               // If mode == size-cap, max KB to include
"dual_submit": true              // Submit to all connected nodes, not just primary
```

---

## Core Changes to CKPool

### 1. Block Template Handling (`workbase.c` / `jobmaker.c`)

- Hook after **GBT (getblocktemplate)** fetch.
- Add pruning step:
  - If `lean_blocks=off`: keep normal tx list.
  - If `coinbase-only`: strip all tx except coinbase.
  - If `top-n`: sort tx by fee and include only `lean_maxtx`.
  - If `size-cap`: include tx until `lean_maxkb`.
- Rebuild **merkle root** accordingly.
- Adjust `coinbasevalue` to reflect removed tx fees.

### 2. Block Validation Preflight

- Before `submitblock`, call GBT with `mode:"proposal"` to ensure trimmed block is still valid.
- Only broadcast if node returns `"accept"`.

### 3. Submission Flow (`submitblock.c`)

- Add support for **dual submit**:
  - Always send block to both primary and secondary BCH nodes.
  - Log if one node rejects but the other accepts.

### 4. Config Parser (`config.c`)

- Add parsing for new `lean_blocks`, `lean_mode`, etc.

### 5. Metrics & Logging

- Log whether block was lean or full.
- Log size, tx count, and propagation latency.
- Expose new JSON metrics: `lean_blocks_enabled`, `lean_mode`, `tx_included`.

---

## When to Use Lean Blocks

- **Best when renting ≥50 PH** or running bursts — because propagation delay (100–200 ms advantage) can decide between win/loss.
- **Less useful at baseline hashrate (\~20–30 PH)** since fee income lost is proportionally higher than stale risk.
- **If mempool is thin (<500 tx)**: lean blocks sacrifice little fees but gain speed → good tradeoff.
- **If mempool is thick (>50k tx)**: fees are more valuable → better to mine full blocks unless you are competing with massive burst.

---

## Test Plan

1. **Unit Tests:**
   - Check block creation with each lean mode.
   - Verify merkle root recalculation matches stripped tx set.
2. **Integration Tests:**
   - Submit pruned block to BCH testnet → confirm acceptance.
   - Compare propagation speed vs. full blocks.
3. **Performance Test:**
   - Run 100 PH burst with lean mode ON vs OFF.
   - Measure stale rate, block acceptance, and block reward differences.

---

## Backward Compatibility

- Default = **off** (full blocks, current CKPool behavior).
- Enabling lean mode requires explicit config.
- No change in mining work format — miners still receive valid stratum work.

---

## Deliverables

- Updated CKPool fork with lean block pruning logic.
- Configurable toggles via `ckpool.conf`.
- Logging and metrics to analyze impact.

---

✅ With this, you can toggle lean mode dynamically depending on whether you’re running steady solo mining or large burst rentals.



---

## Operational Guidance — When to Use Lean Blocks

- **Best for bursts / rentals:** Enable when you temporarily push high hashrate (≈ **≥120–150 PH/s**) and want the fastest propagation to reduce orphan risk.
- **Economics rule of thumb:** Favor lean mode when `(Δorphan_prob × 3.125 BCH) > fees_lost`. On BCH, fees per block are often **0.02–0.10 BCH**; lean blocks can lower orphan risk by **0.2–0.5%** in tight races.
- **Run full blocks** for steady, non‑burst mining when you value fees or your observed orphan rate is already negligible.
- **Modes:**
  - `coinbase_only` → maximum speed, zero fees.
  - `top_n=1` → almost as fast, recovers a bit of fees.
  - `size_cap` (e.g., 50 KB) → compromise between speed and fees.

## Backward Compatibility & Safety

- **Default off:** `lean_blocks=false` → behavior is **identical** to today.
- **Auto‑fallback:** If lean preflight (`getblocktemplate` with `mode:"proposal"`) returns an error (e.g., `bad-cb-amount`), disable lean for the current height and fall back to a full template.
- **Runtime toggles:** SIGHUP config reload or `ckpoolctl` admin commands (`lean on|off`, `lean mode`, `status`).
- **Dual submission:** On solve, submit the block to **both** configured RPC nodes; ignore `duplicate` on the second.

## Config Additions (example)

```json
{
  "lean_blocks": false,
  "lean_mode": "coinbase_only",   // coinbase_only | top_n | size_cap
  "lean_maxtx": 0,                 // used by top_n
  "lean_maxsize_kb": 50,           // used by size_cap
  "lean_minfeerate_sat_kb": 0,     // optional filter; 0=ignore
  "dual_submit": true,
  "lean_autoswitch": {
    "enabled": true,
    "min_burst_ph": 120,
    "max_fee_bch": 0.05,
    "min_orphan_gain_bp": 20
  }
}
```

## Code Change Map (ckpool fork)

> Names are indicative—adapt to your tree.

1. **Config Parser** (e.g., `conf.c`)

- Parse fields above; set defaults so the old path stays unchanged.

2. **Template Fetcher** (e.g., `rpc.c:get_block_template()`)

- Unchanged RPC call; return `Template { header, coinbasevalue, transactions[] (fee/hash/data/depends) }`.

3. **Lean Pruner** (new `lean.c`)

```c
bool build_lean_template(const Template *in, Template *out, const Cfg *cfg) {
  *out = *in; out->transactions.clear();
  uint64_t fees_all = sum_fees(in->transactions);
  uint64_t subsidy  = in->coinbasevalue - fees_all; // BCH has no witness subsidy split

  vector<Tx> K;
  if (cfg->lean_mode == COINBASE_ONLY) {
    // keep none
  } else if (cfg->lean_mode == TOP_N) {
    K = select_top_n_by_feerate(in->transactions, cfg->lean_maxtx);
  } else if (cfg->lean_mode == SIZE_CAP) {
    K = pack_until_size(in->transactions, cfg->lean_maxsize_kb*1024, cfg->lean_minfeerate_sat_kb);
  }

  uint64_t fees_kept = sum_fees(K);
  out->coinbasevalue = subsidy + fees_kept;  // **critical**
  out->coinbase = build_coinbase(out->coinbasevalue, in->coinbase_extranonce_layout);
  out->transactions = K;
  out->merkle_root = merkle_root(out->coinbase, out->transactions);
  return true;
}
```

- `select_top_n_by_feerate`/`pack_until_size` must only include tx with **no unresolved **``.

4. **Job Builder** (e.g., `stratum.c:publish_job()`)

```c
Template t = rpc_getblocktemplate();
Template j = t;
if (cfg.lean_blocks && autoswitch_allows(cfg)) {
  if (!build_lean_template(&t, &j, &cfg)) j = t;
  if (!gbt_proposal_ok(j)) { log_warn("lean preflight failed; fallback"); j = t; stats.lean_autodisable++; }
}
publish_stratum_job(j);
```

5. **GBT Proposal Preflight** (e.g., `rpc.c:gbt_proposal_ok()`)

```c
bool gbt_proposal_ok(const Template &j) {
  std::string hex = assemble_block_hex(j);
  auto r = rpc_call("getblocktemplate", {{"mode","proposal"},{"data",hex}});
  return r.is_null();
}
```

6. **Solve Path / Dual Submit** (e.g., `submit.c:on_block_solve()`)

```c
std::string hex = assemble_block_hex(current_job_template);
rpc_submitblock(primary,   hex);
rpc_submitblock(secondary, hex); // ignore duplicate
```

7. **Metrics & Logging**

- Per job: `LEAN_BLOCK=true|false`, `lean_kept_tx`, `lean_fees_kept`, `lean_fees_dropped`, `template_size_bytes`.
- Per solve: dual‑submit results; `announce_to_publish_ms` (ZMQ→job latency).

8. **Admin CLI (optional)**

- `ckpoolctl lean on|off`, `ckpoolctl lean mode ...`, `ckpoolctl status`.

## Testing & Rollout

- **Unit:** merkle recompute; coinbase math; `depends` handling; size estimation.
- **Regtest:** coinbase‑only and top‑1 variants pass `proposal` and mine accepted blocks.
- **Canary:** enable during bursts; monitor `orphan_rate`, `fees_dropped`, `reject%`.
- **Revert:** feature‑flag off returns behavior to current ckpool (bit‑for‑bit on headers for the same GBT).

