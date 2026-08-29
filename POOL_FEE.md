# Pool Fee System — Solo Mode Payment Splitting

BlockSniper.ai implements a dual-output coinbase mechanism that automatically splits block rewards between miners and the pool operator. This document explains the mechanics, configuration, and verification.

## How It Works

### Dual-Output Coinbase

When a solo miner finds a block, the pool creates a coinbase transaction with **two outputs**:

1. **Miner Output**: Pays the found-block value to the miner's own BCH address — their stratum username — in solo mode (`-B`). It falls back to `bchaddress` in two cases: a solo miner whose username is not address-shaped, and regular (non-solo) pool mode, where every block pays `bchaddress`
2. **Fee Output**: Pays the pool operator's fee to `pooladdress`

**Example with 6.25 BCH block and 2% fee:**
```
Block Reward:        3.125 BCH
Pool Fee (2%):       0.0625 BCH (fee amount)
Miner Receives:      3.0625 BCH (remainder: 3.125 - 0.0625)

Coinbase Outputs:
  - Output 1: 3.0625 BCH → Miner's address
  - Output 2: 0.0625 BCH → Pool operator address
  - Total:    3.125 BCH (sum invariant maintained)
```

### Fee Calculation & Rounding

The fee is calculated as: `fee = block_reward * (poolfee / 100)`, then **rounded down** to the nearest satoshi.

**Example calculations:**
- 6.25 BCH, 2.0% fee → 0.125 BCH (12,500,000 sats)
- 3.125 BCH, 1.5% fee → 0.046875 BCH (4,687,500 sats) — exact
- 6.25 BCH, 1.0% fee → 0.0625 BCH (6,250,000 sats) — exact
- 1.0 BCH, 2.0% fee → 0.02 BCH (2,000,000 sats) — exact
- 0.5 BCH, 2.0% fee → 0.01 BCH (1,000,000 sats) — exact

If rounding down produces **dust** (< 546 sats), the fee output is **omitted entirely**:
- The entire block reward goes to the miner
- No fee output is created
- This avoids creating unspendable dust outputs

**Dust omission example:**
- 0.001 BCH block, 2% fee → fee would be 0.00002 BCH (2,000 sats)
- 2,000 sats > 546 sats → fee output is created ✓
- 0.0001 BCH block, 2% fee → fee would be 0.000002 BCH (200 sats)
- 200 sats < 546 sats → **fee output omitted**, miner gets full 0.0001 BCH

### Solo Mode Payment Flow

1. **Miner connects** with username = their BCH address (e.g., `bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy`)
2. **Miner finds a block** (solves valid share at network difficulty)
3. **Pool creates coinbase** with dual outputs:
   - Miner's output: block_reward - fee → miner's address
   - Fee output: fee amount → pooladdress
4. **Block is broadcast** to the network
5. **On block confirmation**, miner receives payment directly on-chain, non-custodial

**No UTXO pooling**: Each block creates its own distinct outputs; the pool takes no custody of funds.

## Configuration

### Essential Keys

```json
{
    "bchaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "pooladdress": "bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",
    "poolfee": 2.0
}
```

- **`bchaddress`** (required for solo mode)
  - Receives payments when miner username is NOT a valid BCH address (fallback)
  - Also used as coinbase message recipient if no `pooladdress` configured
  - Supports CashAddr (with/without prefix: `bitcoincash:` / `bchtest:` / `bchreg:`) and legacy Base58

- **`pooladdress`** (required for dual-output fee splitting)
  - The pool operator's BCH address (receives the configured `poolfee` percentage)
  - Same address formats as `bchaddress`
  - Should be distinct from `bchaddress` — **not enforced in code**, but see
    the fallback note under *Solo Mode with Smart Fallback* for what happens
    when they are equal
  - Validated at stratifier startup. If bitcoind rejects it, the pool logs
    `Pool fee address ... is invalid, disabling pool fee`, sets `poolfee` to 0
    and keeps running — collecting nothing. Grep the log for
    `Pool operator fee address valid` after any config change

- **`poolfee`** (configurable, default production: 2.0)
  - Fee percentage, expressed as a percent of the block reward
  - Can be integer or decimal (0, 1, 1.5, 2.0, 10.5, etc.)
  - **Clamped** to [0, 50] with a warning — a value above 50 is lowered to 50,
    not rejected, and the pool starts anyway
  - Rounding: fees are always rounded down; dust outputs are omitted
  - Example: 2.0 = 2% pool fee (miner receives 98%)

### Deprecated Key (Still Supported)

```json
{
    "btcaddress": "..."
}
```

**`btcaddress`** is a deprecated alias for `bchaddress`. Both keys work identically. Use `bchaddress` in new configurations for clarity (BCH-specific naming).

### Complete Example

```json
{
    "btcd": [{
        "url": "127.0.0.1:8332",
        "auth": "rpcuser",
        "pass": "rpcpassword",
        "notify": true,
        "zmqnotify": "tcp://127.0.0.1:28333"
    }],
    "bchaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "pooladdress": "bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",
    "poolfee": 2.0,
    "btcsig": "YourPoolName.com",
    "serverurl": ["0.0.0.0:3333"],
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000
}
```

## Verification & Inspection

### Using the Regression Test Suite

BlockSniper.ai includes an end-to-end test suite at `testing/regtest-e2e.sh` that:
- Mines blocks in regtest mode
- Verifies dual-output coinbase creation
- Confirms fee calculations are correct
- Tests dust omission behavior
- Validates network-specific address handling

**Run the full test:**
```bash
cd /path/to/ckpool
./testing/regtest-e2e.sh
```

### Manual Block Inspection

To inspect a mined block and verify the fee split:

```bash
# Get a recent block hash
BLOCK_HASH=$(bitcoin-cli getblockhash BLOCK_HEIGHT)

# Inspect the block's coinbase outputs
bitcoin-cli getblock "$BLOCK_HASH" 2 | jq '.tx[0].vout'
```

**Example output (6.25 BCH block, 2% fee):**
```json
[
  {
    "value": 6.125,
    "scriptPubKey": {
      "address": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy"
    }
  },
  {
    "value": 0.125,
    "scriptPubKey": {
      "address": "bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w"
    }
  }
]
```

- **Output 0**: 6.125 BCH → Miner's address
- **Output 1**: 0.125 BCH → Pool operator's address

### Testnet Examples

These blocks on BCH testnet verify the system works:

| Block | Miner | Fee | Result |
|-------|-------|-----|--------|
| 1677558 | — | 1% | ✓ Dual-output confirmed |
| 1677572 | — | 2% | ✓ Dual-output confirmed |

To inspect these:
```bash
# Mainnet/testnet node
bitcoin-cli getblock 1677558 2 | jq '.tx[0].vout | length'  # Should show 2 outputs
bitcoin-cli getblock 1677558 2 | jq '.tx[0].vout[] | .value'
```

## Solo Mode with Smart Fallback

### Username Validation

When a miner connects with a username:

1. **Valid BCH address** (any form: CashAddr with prefix, without prefix, or legacy Base58)
   - Address is **checksum-verified** locally
   - Must be correct network (mainnet/testnet/regtest)
   - ✅ Accepted: Miner is paid to this address when finding a block

2. **Invalid address** (looks like an address but fails checksum/network)
   - ❌ Rejected immediately with message: "Invalid BCH address (bad checksum or wrong network) - check your username for typos"
   - Protects miners from accidentally donating a block

3. **Non-address username** (e.g., `rig01`, `worker1`)
   - ✅ Accepted: Miner is authorized and mines for the pool's `bchaddress`
   - The user's payout script is copied from the pool's own at authorisation
     (`stratifier.c`, `generate_user()` → `user->pool_fallback = true`), so a
     block they find pays `bchaddress` — **not** `pooladdress`
   - **The fee output is still cut.** The split is built into the shared
     workbase and is gated only on `poolvalid && poolfee > 0` and the dust
     check — never on `pool_fallback`. A fallback block pays
     `(100 - poolfee)%` to `bchaddress` and `poolfee%` to `pooladdress`,
     exactly like an address-based miner's block.
   - This is why `bchaddress` and `pooladdress` should be **distinct**: set
     them to the same address and a fallback block carries two coinbase
     outputs to that one address, which coinbase parsers have to special-case.

### Example: Typo Protection

```bash
# Correct address → mining starts
./cgminer -u bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy

# Typo in address (bad checksum) → rejected
./cgminer -u bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfui
# Error: "Invalid BCH address (bad checksum or wrong network) - check your username for typos"

# Non-address name → mines for pool fallback
./cgminer -u myrig01
# Mining for bchaddress (pool fallback)
```

## Rentals & Auto-Detection

When NiceHash or MiningRigRentals connect, the pool auto-detects via useragent and applies configured difficulty (not overridable by mindiff_overrides pattern matching):

- **NiceHash**: `500000` difficulty (configurable via config)
- **MiningRigRentals**: `1000000` difficulty (configurable via config)

Each rental rental service still uses their username (usually an address or username), and if an address, is paid directly when finding a block.

## Security & Considerations

### Non-Custodial Payment

- Payments are made directly on-chain in the coinbase (block reward)
- The pool never holds or custodies miner funds
- Upon block confirmation, funds belong solely to the recipient address

### Double-Spend Prevention

- Coinbase outputs are spendable only after 100 block confirmations (Bitcoin/BCH consensus rule)
- No miner can claim the same block reward twice

### Address Validation

- All addresses are validated locally using CashAddr checksum algorithms
- Network detection is automatic (mainnet/testnet/regtest from node)
- Case-insensitive CashAddr (normalized to lowercase after validation)

### Fee Integrity

- Fees are calculated and rounded consistently
- Dust protection prevents creation of unspendable outputs
- Sum invariant: output1 + output2 = block reward (always)

## Troubleshooting

### Fee Not Appearing in Blocks

1. Check pool is running with `-B` flag for solo mode
2. Verify `pooladdress` is configured and distinct from `bchaddress`
3. Verify `poolfee` is > 0 (and not rounded to dust)
4. Inspect block coinbase outputs: `bitcoin-cli getblock <hash> 2`

### Miners Being Rejected

1. Verify address is valid for the network (mainnet/testnet/regtest)
2. Check the rejection message: "Invalid BCH address" means checksum/network mismatch
3. Test address locally: validate it with a BCH address tool or bitcoin-cli

### Incorrect Fee Amount

1. Confirm `poolfee` is a JSON **number**, not a string — `2` and `2.0` are
   both accepted (`json_get_double` takes any `json_is_number`), but `"2.0"`
   in quotes logs `Json entry poolfee is not a number` and leaves the fee at 0
2. Verify poolfee is in range [0, 50] — above 50 it is clamped down to 50 and
   the pool logs `Poolfee ... out of range, clamping to 50` at startup
3. Check if fee rounds to dust (< 546 sats) — if so, fee output is omitted
4. Inspect the block with `bitcoin-cli getblock <hash> 2`

---

*BlockSniper.ai Pool Fee System — Non-custodial, dual-output, solo mining with automatic operator fee distribution*
