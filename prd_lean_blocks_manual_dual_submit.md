# PRD — Lean Blocks (Manual) + Dual Submit

**Scope:** Minimal feature set for your ckpool fork. No autoswitching. You decide when to enable lean blocks. Also includes node (`bitcoin.conf`) changes for your two BCHN nodes.

---

## 1) Goals

- Add a **manual** `lean_blocks` mode to mine tiny blocks for faster propagation.
- Support three **manual modes**: `coinbase_only`, `top_n`, `size_cap`.
- Keep default behavior **unchanged** (full blocks) when disabled.
- On solve, **submit to both nodes** (primary + secondary) for redundancy.

---

## 2) When to use

- **Bursts/rentals** (≥ 50–100 PH): turn **ON** (prefer `coinbase_only` or `top_n:1`).
- **24×7 baseline**: keep **OFF** to earn all fees.
- If mempool fees are tiny (≤ 0.05 BCH), lean mode is usually worth it during bursts.

---

## 3) ckpool.conf additions (manual control only)

```json
{
  "lean_blocks": false,                 // default OFF
  "lean_mode": "coinbase_only",       // coinbase_only | top_n | size_cap
  "lean_maxtx": 0,                      // only used by top_n
  "lean_maxsize_kb": 50,                // only used by size_cap
  "dual_submit": true                   // submit block to both RPC nodes
}
```

**Profiles to copy/paste:**

- **Burst (max speed)**

```json
{"lean_blocks": true, "lean_mode": "coinbase_only", "dual_submit": true}
```

- **Burst (tiny fee)**

```json
{"lean_blocks": true, "lean_mode": "top_n", "lean_maxtx": 1, "dual_submit": true}
```

- **Normal**

```json
{"lean_blocks": false, "dual_submit": true}
```

---

## 4) Code changes in your ckpool fork

> File/function names are indicative—adapt to your tree.

### 4.1 Config parser (e.g., `conf.c`)

- Parse: `lean_blocks`, `lean_mode`, `lean_maxtx`, `lean_maxsize_kb`, `dual_submit` (defaults above).

### 4.2 Template fetch → prune → job (e.g., `rpc.c`, `jobmaker.c`)

1. `t = rpc_getblocktemplate()` (unchanged).
2. If `lean_blocks==true`, call **pruner**:

```c
bool build_lean_template(const Template *in, Template *out, const Cfg *cfg);
```

3. Rebuild **coinbase** (with corrected `coinbasevalue`) and **merkle root** from kept txs.
4. **Preflight** with `getblocktemplate {mode:"proposal", data:<blockhex>}`; on failure → **fallback** to the unmodified template for this height (log reason).
5. Publish the job.

### 4.3 Pruner (new `lean.c`)

```c
bool build_lean_template(const Template *in, Template *out, const Cfg *cfg) {
  *out = *in; out->transactions.clear();
  uint64_t fees_all = sum_fees(in->transactions);
  uint64_t subsidy  = in->coinbasevalue - fees_all; // BCH has no witness splits
  vector<Tx> K;
  switch (cfg->lean_mode) {
    case COINBASE_ONLY: /* keep none */ break;
    case TOP_N:         K = select_top_n_independent(in->transactions, cfg->lean_maxtx); break;
    case SIZE_CAP:      K = pack_independent_until_size(in->transactions, cfg->lean_maxsize_kb*1024); break;
  }
  uint64_t fees_kept = sum_fees(K);
  out->coinbasevalue = subsidy + fees_kept;   // **critical**
  out->coinbase      = build_coinbase(out->coinbasevalue, in->coinbase_extranonce_layout);
  out->transactions  = K;
  out->merkle_root   = merkle_root(out->coinbase, out->transactions);
  return true;
}
```

- **Independent** = tx with no unresolved `depends` (include parents or skip).

### 4.4 Solve path (e.g., `submit.c`)

```c
std::string hex = assemble_block_hex(current_job_template);
rpc_submitblock(primary,   hex);
rpc_submitblock(secondary, hex);   // accept "duplicate" on second
```

### 4.5 Logging/metrics

- Per job: `LEAN_BLOCK=bool`, `lean_kept_tx`, `lean_template_kb`, `fees_kept`, `fees_dropped`.
- Per solve: primary result, secondary result, proposal preflight time/result.

### 4.6 Backward compatibility

- If `lean_blocks=false`, **do not** call pruner; jobs remain identical to current behavior.

---

## 5) Node configs (`bitcoin.conf`) for your two BCH nodes

Assume: **Node A = primary (full‑fee)**, **Node B = secondary (burst‑lean capable)**.

### 5.1 Common essentials (both nodes)

```
server=1
rpcuser=bchadmin
rpcpassword=<yours>
rpcallowip=10.12.112.0/24
rpcthreads=8
zmqpubhashblock=tcp://0.0.0.0:28333
# (optional) also:
# zmqpubhashblock=tcp://0.0.0.0:28334  (use distinct ports per node in ckpool config)
maxconnections=64
# Compact blocks (BIP152) are on by default in BCHN; no special flag required.
```

### 5.2 Node A (full blocks, fees priority — your *normal* mode)

```
# Keep full mempool for maximum fees
blocksonly=0
# Allow big templates (default is fine); you can omit these
blockmaxsize=0
blockmintxfee=0.00001
minrelaytxfee=0.00001
```

### 5.3 Node B (burst‑lean profile — only when you want tiny blocks)

> You can keep this node running like normal and flip these settings when you plan to burst; or run it permanently with a lean mempool.

```
# Trim mempool so GBT is naturally lean
blocksonly=1                 # don't relay tx → empty mempool over time
blockmaxsize=50000           # ~50 KB target blocks
blockmintxfee=0.1            # effectively exclude mempool tx even if any arrive
minrelaytxfee=0.1            # prevents low‑fee tx from sticking around
```

**How to use with ckpool:** point ckpool **RPC** to Node B only when you enable `lean_blocks`. Keep ZMQ from **both** nodes at all times so tip changes trigger instantly.

> If you prefer not to alter node settings, you can keep both nodes “normal” and rely entirely on ckpool pruning (Section 4). In that case, just ensure Node B exists for **dual‑submit** redundancy.

---

## 6) Test plan (minimal)

1. **Regtest/testnet:** mine with `coinbase_only` and `top_n:1`; `getblocktemplate` `proposal` returns `null`; blocks accepted.
2. **Mainnet canary:** enable during a short burst; confirm tiny block sizes and normal acceptance; track fees dropped and any orphan.
3. **Revert check:** set `lean_blocks=false` and verify headers/jobs match your current release.

---

## 7) Quick operator checklist

- Toggle profile in `ckpool.conf` (no autoswitch): ON for bursts, OFF for baseline.
- Ensure ZMQ from **both** nodes is configured in ckpool.
- Keep dual‑submit enabled.
- Monitor `reject%`, `orphan`, and `fees_dropped` in logs.

