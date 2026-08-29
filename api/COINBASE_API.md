# Coinbase API Endpoint

## Overview

The `/coinbase` endpoint connects to your CKPool stratum server, retrieves the current mining work, and returns detailed information about the coinbase transaction including pool fee splits.

This allows you to display real-time coinbase information to miners, similar to letsmine.it.

## Endpoint

```
GET /coinbase?user=<username>
```

### Parameters

- `user` (optional): Username to display in the response. Defaults to "anonymous" if not provided.

### Headers

```
Authorization: Bearer YOUR_API_KEY
```

## Response Format

```json
{
  "username": "skaisser",
  "coinbase_hex": "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff2a03c4080e000423f8e768043c73e2220c0d456c6f506f6f6c2e636c6f7564ffffffff0263924212000000001976a91401c09ad61cb2ef44f812441153318c332d3b651088ac40665f00000000001976a914f28cb5db41d635137309e5a4bd7987255197e09888ac00000000",
  "coinbase_message": "EloPool.cloud",
  "outputs": [
    {
      "value": 306184547,
      "value_bch": "3.06184547",
      "address": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
      "type": "miner"
    },
    {
      "value": 6251840,
      "value_bch": "0.06251840",
      "address": "1P7V69n7kiJojJ6iJfNyJcuS2TPW14hLaN",
      "type": "pool_fee"
    }
  ],
  "total_value": 312436387,
  "total_value_bch": "3.12436387",
  "block_height": 919747,
  "network_bits": "18019a90",
  "timestamp": 1760031366
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `username` | string | The username parameter provided in the request |
| `coinbase_hex` | string | Full coinbase transaction in hexadecimal format |
| `coinbase_message` | string | Pool branding message extracted from coinbase (e.g., "EloPool.cloud") |
| `outputs` | array | Array of coinbase outputs (miner reward + pool fee) |
| `total_value` | integer | Total block reward in satoshis |
| `total_value_bch` | string | Total block reward formatted in BCH |
| `block_height` | integer | Current block height being mined |
| `network_bits` | string | Network difficulty bits in hex format |
| `timestamp` | integer | Unix timestamp when the response was generated |
| `error` | string | Error message if request failed (only present on error) |

### Output Object

Each output in the `outputs` array contains:

| Field | Type | Description |
|-------|------|-------------|
| `value` | integer | Output value in satoshis |
| `value_bch` | string | Output value formatted in BCH (8 decimal places) |
| `address` | string | Bitcoin Cash address receiving the output |
| `type` | string | "miner" for main reward, "pool_fee" for operator fee |

## Example Usage

### cURL

```bash
curl -H "Authorization: Bearer your_api_key_here" \
  "http://localhost:8888/coinbase?user=myworker"
```

### JavaScript (fetch)

```javascript
const response = await fetch('http://localhost:8888/coinbase?user=myworker', {
  headers: {
    'Authorization': 'Bearer your_api_key_here'
  }
});

const data = await response.json();
console.log('Coinbase message:', data.coinbase_message);
console.log('Miner will receive:', data.outputs[0].value_bch, 'BCH');
console.log('Pool fee:', data.outputs[1].value_bch, 'BCH');
```

### Python

```python
import requests

headers = {'Authorization': 'Bearer your_api_key_here'}
response = requests.get(
    'http://localhost:8888/coinbase?user=myworker',
    headers=headers
)

data = response.json()
print(f"Mining to: {data['outputs'][0]['address']}")
print(f"Miner reward: {data['outputs'][0]['value_bch']} BCH")
print(f"Pool fee: {data['outputs'][1]['value_bch']} BCH")
```

## Caching

- Responses are cached for **10 seconds**
- Each username has its own cache entry
- Cache is automatically invalidated after TTL expires

## Use Cases

### 1. Display Current Block Reward

Show miners exactly what they'll receive when a block is found:

```javascript
const coinbase = await getCoinbaseInfo('myworker');
console.log(`If you find a block now, you'll receive ${coinbase.outputs[0].value_bch} BCH`);
```

### 2. Verify Pool Fee

Allow miners to verify the pool is taking the correct fee percentage:

```javascript
const total = parseFloat(coinbase.total_value_bch);
const fee = parseFloat(coinbase.outputs[1].value_bch);
const feePercentage = (fee / total * 100).toFixed(2);
console.log(`Pool fee: ${feePercentage}%`);
```

### 3. Display Pool Branding

Show the pool's coinbase message to confirm identity:

```javascript
console.log(`Mining on: ${coinbase.coinbase_message}`);
```

### 4. Transaction Transparency

Display the full coinbase hex for miners who want to verify the exact transaction:

```html
<details>
  <summary>View Raw Coinbase Transaction</summary>
  <code>{coinbase.coinbase_hex}</code>
</details>
```

## Error Handling

If the request fails, the response will contain an `error` field:

```json
{
  "username": "myworker",
  "timestamp": 1760031366,
  "error": "Failed to connect to pool: connection refused"
}
```

Common errors:
- `Failed to connect to pool`: CKPool stratum is not running or not accessible
- `Failed to get coinbase from pool`: Pool returned invalid stratum response
- Connection timeout errors if pool is slow to respond

## Configuration

The endpoint connects to the stratum server at `127.0.0.1:3333` by default. This can be changed by modifying `DefaultStratumHost` in the source code.

## Performance

- Connection timeout: 5 seconds
- Read timeout: 10 seconds
- Response cache: 10 seconds per username
- Concurrent requests supported

## Security

- Requires valid API key in `Authorization` header, compared in constant time
- Subject to rate limiting (20 requests per 60 seconds per IP)
- Direct TCP connection to localhost only (not exposed externally)

The `user` parameter is **not** validated or sanitized — an earlier version of
this document claimed it was, which was never true. It is safe today only
because of where it goes, not because of what is done to it: it is `json.Marshal`ed
into the stratum request (so it cannot break out of the message) and concatenated
into a cache key (so an attacker can at worst occupy cache entries). It never
reaches a shell, a file path, or a SQL statement. **Validate it before using this
parameter anywhere else** — `handleUserFile` and `handleUserLog` deliberately run
their own `filepath.Base()` for exactly that reason.
