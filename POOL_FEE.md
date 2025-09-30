# Pool Operator Fee Implementation

## Overview

EloPool supports automatic pool operator fee distribution in the coinbase transaction. This feature creates a dual-output coinbase that splits block rewards between the main mining address and the pool operator's fee address.

## Configuration

Add these parameters to your `ckpool.conf`:

```json
{
    "btcaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "pooladdress": "bitcoincash:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez",
    "poolfee": 1.0
}
```

### Configuration Parameters

- **`btcaddress`**: Main mining address (receives block rewards minus pool fee)
  - Supports CashAddr format: `bitcoincash:`, `bchtest:`, `bchreg:`
  - Supports legacy Base58 addresses
  - **Receives**: (100 - poolfee)% of block reward

- **`pooladdress`**: Pool operator fee address
  - Supports CashAddr format: `bitcoincash:`, `bchtest:`, `bchreg:`
  - Supports legacy Base58 addresses
  - **Receives**: poolfee% of block reward

- **`poolfee`**: Pool operator fee percentage (must be a decimal number)
  - Type: `double` (floating point)
  - Range: 0.0 - 100.0
  - Example: `1.0` = 1%, `2.5` = 2.5%, `0.5` = 0.5%
  - **Important**: Must include decimal point (use `1.0` not `1`)

## How It Works

### Coinbase Transaction Structure

When `pooladdress` and `poolfee` are configured, the pool creates a **2-output coinbase transaction**:

```
Output 0: (100 - poolfee)% → btcaddress (main mining address)
Output 1: poolfee%          → pooladdress (pool operator fee)
```

### Example: 1% Pool Fee

**Configuration:**
```json
{
    "btcaddress": "bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs",
    "pooladdress": "bchtest:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez",
    "poolfee": 1.0
}
```

**Block Reward: 0.390625 BCH**

**Coinbase Outputs:**
- Output 0: 0.38671875 BCH (99%) → `bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs`
- Output 1: 0.00390625 BCH (1%) → `bchtest:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez`

**Verified on BCH Testnet:**
- Block Height: 1677558
- Block Hash: `0000000000091e9319d886807e7c10c00edbecad2ae1cb79b7a224eb4f208248`
- Coinbase Message: `EloPool.cloud/TestNet2`

## Implementation Details

### Code Flow

1. **Configuration Loading** (`src/ckpool.c`)
   - Reads `pooladdress` and `poolfee` from config
   - Stores in `ckpool_t` struct

2. **Address Validation** (`src/stratifier.c`)
   - Validates `pooladdress` with `generator_checkaddr()`
   - Converts to transaction output format with `address_to_txn()`
   - Sets `ckp->poolvalid = true` if address is valid

3. **Coinbase Generation** (`src/stratifier.c:generate_coinbase()`)
   - Calculates fee amount: `fee = coinbasevalue * (poolfee / 100)`
   - Creates 2-output transaction:
     - First output: `coinbasevalue - fee` → btcaddress
     - Second output: `fee` → pooladdress

4. **Output Structure**
   - Outputs stored in `coinb2bin` and `coinb3bin`
   - Transaction output count set to 2
   - Both outputs included in final coinbase transaction

### Priority Order

If multiple fee mechanisms are configured, priority is:

1. **Pool Operator Fee** (`pooladdress` + `poolfee`) - **Highest Priority**
2. **Donation** (`donaddress` + `donation`) - Fallback if no pool fee
3. **Single Output** - If neither configured

### Startup Log Messages

Successful configuration shows:
```
[2025-09-30 08:50:41.287] ckpool stratifier ready
[2025-09-30 08:50:41.289] Pool operator fee address valid bchtest:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez (1.0%)
[2025-09-30 08:50:41.289] Mining from any incoming username to address bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs
[2025-09-30 08:50:41.289] 1.0 percent pool operator fee to bchtest:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez
```

## Production Configuration Examples

### Mainnet with 1% Pool Fee

```json
{
    "btcd": [{
        "url": "10.0.1.10:8332",
        "auth": "rpcuser",
        "pass": "rpcpassword",
        "notify": true,
        "zmqnotify": "tcp://10.0.1.10:28333"
    }],
    "btcaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",
    "pooladdress": "bitcoincash:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez",
    "poolfee": 1.0,
    "btcsig": "EloPool.cloud",
    "serverurl": ["0.0.0.0:3333"],
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "asicboost": true,
    "version_mask": "1fffe000"
}
```

### Testnet with 2.5% Pool Fee

```json
{
    "btcd": [{
        "url": "10.0.0.226:18332",
        "auth": "testuser",
        "pass": "testpass",
        "notify": true,
        "zmqnotify": "tcp://10.0.0.226:28332"
    }],
    "btcaddress": "bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs",
    "pooladdress": "bchtest:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez",
    "poolfee": 2.5,
    "btcsig": "EloPool.cloud/TestNet",
    "serverurl": ["0.0.0.0:3334"],
    "mindiff": 1,
    "startdiff": 10,
    "maxdiff": 1000
}
```

## Troubleshooting

### Error: "Json entry poolfee is not a double"

**Cause**: `poolfee` is specified as integer instead of decimal

**Solution**: Add decimal point:
```json
// ❌ Wrong
"poolfee": 1

// ✅ Correct
"poolfee": 1.0
```

### Warning: "Pool fee address is invalid, disabling pool fee"

**Cause**: `pooladdress` is not a valid Bitcoin Cash address

**Solutions**:
- Verify address format (CashAddr or legacy)
- Check network (mainnet vs testnet address)
- Test address with `bitcoin-cli validateaddress`

### Pool Fee Not Applied

**Check**:
1. Both `pooladdress` and `poolfee` must be configured
2. `poolfee` must be greater than 0
3. Pool must be in pool mode (not solo mode with `-B` flag)
4. Check startup logs for "Pool operator fee address valid"

## Technical Notes

### Address Validation

- CashAddr addresses validated natively (no RPC call)
- Legacy addresses validated via bitcoind RPC
- Both P2PKH and P2SH addresses supported
- Validation happens at pool startup

### Fee Calculation

- Fee calculated as: `fee_satoshis = (block_reward_satoshis * poolfee) / 100`
- Integer arithmetic ensures exact satoshi amounts
- Main output = `block_reward - fee` to guarantee total matches block subsidy + fees

### Coinbase Transaction

- Single transaction with multiple outputs
- No miner payout logic - this is ONLY for block rewards
- Miner payouts (if running a pool with multiple miners) handled separately via shares

## Files Modified

- `src/ckpool.c` - Configuration loading
- `src/ckpool.h` - Data structure definitions
- `src/stratifier.c` - Coinbase generation and validation
- Configuration files - Added `pooladdress` and `poolfee` parameters

## Testing

Tested successfully on Bitcoin Cash testnet:
- Block 1677558 confirmed with 2-output coinbase
- 99% to btcaddress, 1% to pooladdress
- CashAddr format addresses working correctly
- No transaction validation errors

## Future Enhancements

Potential improvements for future versions:

1. **Dynamic Fee Adjustment**: Allow fee to change based on block height or time
2. **Multiple Fee Recipients**: Support more than 2 outputs for complex fee structures
3. **Fee Cap**: Set maximum fee in absolute BCH amount
4. **Time-based Fees**: Different fees for different time periods

## Support

For issues or questions:
- GitHub Issues: https://github.com/skaisser/ckpool/issues
- Review code changes in commit related to pool fee implementation

---

**Note**: This feature is production-ready and has been tested on BCH testnet. Always test configuration changes on testnet before deploying to mainnet.