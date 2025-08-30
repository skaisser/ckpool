# Product Requirements Document (PRD)

## Title

**Enable Lean Blocks Mode in ckpool Fork**

## Author

Shirleyson Kaisser

## Date

2025-08-30

## Summary

Introduce a configuration option (`lean_blocks`) to ckpool that allows mining with near-empty block templates (coinbase + optionally a few high-priority transactions). This reduces block propagation latency and improves competitiveness in high-variance solo mining bursts, at the expense of leaving most transaction fees behind.

---

## Goals

- Add a **configurable flag** (`lean_blocks: true|false`) to enable/disable lean block template generation.
- When enabled, ckpool should request block templates from the node with **minimal or no transactions**.
- Allow flexibility: either **coinbase-only** or **coinbase + X high-fee txns** (configurable max).
- Preserve backward compatibility: default = `false` (normal full blocks).

---

## Non-Goals

- Do not modify core BCH node code (rely on existing `getblocktemplate` options).
- Do not alter share submission or stratum protocol.
- Do not attempt to filter specific transactions — just use blockmaxsize/maxtx configs.

---

## Functional Requirements

1. **Configuration**

   - Add new JSON option in `ckpool.conf`:
     ```json
     "lean_blocks": true,
     "lean_maxtx": 0  // number of transactions allowed, 0 = coinbase only
     ```
   - Defaults:
     - `lean_blocks = false`
     - `lean_maxtx = unlimited`

2. **Template Request Logic**

   - When `lean_blocks = true`:
     - Call `getblocktemplate` with restricted parameters (use `-blockmaxsize`, `-blocksonly`, or prune template txns internally).
     - Ensure coinbase value reflects full subsidy + available fees (even if not included).
     - Strip or truncate txns to match `lean_maxtx`.

3. **Propagation Safety**

   - Validate lean block before broadcasting.
   - Submit via both configured nodes for redundancy.
   - Log a warning if block template generated fewer txns than mempool size (to confirm lean mode active).

4. **Metrics / Logging**

   - In pool logs, tag solved blocks with `LEAN_BLOCK=true` when lean mode is active.
   - Log how many txns were included vs. mempool size.

---

## Technical Considerations

- BCH `getblocktemplate` allows limiting block size via `blockmaxsize` (set to \~50 KB for lean mode).
- Alternatively, filter transactions inside ckpool after retrieving template.
- Must ensure `coinbasevalue` is correct even if fees are not included → validate with node before submission.
- Failover: if lean mode misbehaves, ckpool should revert to full block template.

---

## Risks

- **Fee loss**: by design, transaction fees are mostly ignored.
- **Propagation advantage not guaranteed**: depends on peers and compact block support.
- **Implementation bug risk**: incorrectly pruning txns could invalidate blocks.

---

## Success Metrics

- Configurable lean mode toggle works.
- When enabled, mined blocks consistently show \~0–20 txns regardless of mempool size.
- No invalid blocks generated.
- Reject rate remains <0.1%.

---

## Next Steps

-

