# EloPool - Production-Ready Bitcoin Cash Mining Pool Software

**EloPool** is a heavily enhanced fork of CKPool, specifically optimized for Bitcoin Cash (BCH) mining. This production-ready pool software includes native CashAddr support, pool operator fee distribution, multi-difficulty management, and enterprise-grade reliability features.

## 🏆 Production Achievements
- **Successfully mining on BCH testnet** since September 2025
- **10+ blocks mined** with proper fee distribution
- **Native CashAddr implementation** (no external dependencies)
- **Battle-tested** with real ASIC hardware (Bitaxe)

## 🚀 Key Features

### Core CKPool Features
- **Ultra-low overhead** massively scalable multi-process, multi-threaded architecture
- **Multiple deployment modes**: Pool, Solo, Proxy, Passthrough, Node
- **Seamless restarts** with socket handover for zero-downtime upgrades
- **ASICBoost support** for improved mining efficiency
- **Advanced vardiff** algorithm with stable high-difficulty handling

### EloPool Major Enhancements (2025)

#### 1. **Pool Operator Fee System** ✅ NEW!
  - Automatic fee distribution in coinbase transaction
  - Dual-output coinbase splitting (miner + pool operator)
  - Configurable percentage (0.0% - 100.0%)
  - **Testnet Verified**: Blocks 1677558 (1% fee), 1677572 (2% fee)
  - Clean implementation without donation code
  - [Full Documentation](POOL_FEE.md)

#### 2. **Native CashAddr Support** ✅
  - Full Bitcoin Cash address format support
  - Zero external dependencies (pure C implementation)
  - Supports all BCH prefixes:
    - `bitcoincash:` (mainnet)
    - `bchtest:` (testnet)
    - `bchreg:` (regtest)
  - Proper 5-bit to 8-bit base32 conversion
  - Polymod checksum verification
  - Backward compatible with legacy addresses
  - **Testnet Proven**: 10+ blocks successfully mined

#### 3. **Advanced Multi-Difficulty Management** ✅

**Three Methods of Difficulty Control (Priority Order):**

##### a) **Password-Based Difficulty** (Highest Priority)
  - Set difficulty via password field: `-p d=500000` or `-p diff=1000000`
  - Overrides ALL other difficulty settings
  - Applied immediately upon authorization
  - Perfect for individual miner control
  - Examples:
    ```bash
    # Short format
    ./bfgminer -o stratum+tcp://pool:3333 -u wallet.worker -p d=500000

    # Long format
    ./cgminer -o stratum+tcp://pool:3333 -u wallet.worker -p diff=1000000
    ```

##### b) **Useragent-Based Detection** (Auto-Detection) 🆕
  - **Automatically detects rental services** from mining.subscribe
  - No special configuration needed by miners!
  - Applied immediately during connection
  - Supported services:
    - **NiceHash**: Detects `"NiceHashMiner"` in useragent → 500k diff
    - **MiningRigRentals**: Detects `"MiningRigRentals"` → 1M diff
  - Works exactly like AsicSteer and other modern pools

##### c) **Worker Name Pattern Matching** (Config-Based)
  - Configure patterns in `mindiff_overrides`:
    ```json
    "mindiff_overrides": {
        "nicehash": 500000,      // Matches: wallet.nicehash_rig1
        "MiningRigRentals": 1000000,  // Matches: wallet.MiningRigRentals_xyz
        "bitaxe": 100,           // Matches: wallet.bitaxe_home
        "high": 2000000          // Matches: wallet.high_performance
    }
    ```
  - Case-insensitive substring matching
  - Applied during worker authorization
  - Useful for custom miner groups

#### 4. **Multi-Node Redundancy** ✅
  - Connect to multiple BCH nodes simultaneously
  - ZeroMQ (ZMQ) for instant block notifications
  - Automatic failover between nodes
  - Load distribution for getblocktemplate calls
  - Eliminates single point of failure

#### 5. **Fully Configurable Coinbase** ✅
  - Complete control via `btcsig` parameter
  - No hardcoded "ckpool" text
  - Pool operators have full branding flexibility
  - Supports up to 38 bytes of custom text

#### 6. **Bitcoin Cash Optimizations**
  - SegWit code completely removed
  - Optimized for ASIC miners (default 500k+ difficulty)
  - BCH-specific block validation
  - Proper ASERT DAA handling

## 📋 Requirements

- **Operating System**: Ubuntu 18.04+ or Debian 10+
- **Dependencies**: 
  - Build tools: `build-essential autoconf automake libtool`
  - Libraries: `libssl-dev libjansson-dev libzmq3-dev`
- **Bitcoin Cash Node**: One or more BCH full nodes with RPC and ZMQ enabled

## 🛠️ Installation

### Quick Install (Production)

```bash
# Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# Run the installer
./install-ckpool.sh
```

### Development/Testing Install

```bash
# Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# Build from current directory
./install-local.sh
```

## ⚙️ Configuration

### Pool Operator Fee Configuration

To enable automatic pool fee distribution:

```json
{
    "btcaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",  // Miner receives 99%
    "pooladdress": "bitcoincash:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez", // Pool receives 1%
    "poolfee": 1.0  // 1% pool fee (must include decimal)
}
```

This creates a dual-output coinbase transaction automatically splitting the block reward.

### Coinbase Message (btcsig)

The `btcsig` parameter controls the **entire** coinbase message that appears in mined blocks. There is no hardcoded text - whatever you set in `btcsig` is exactly what will appear in the blockchain.

**Examples:**
- `"btcsig": "MyPool.com"` → Coinbase shows: `MyPool.com`
- `"btcsig": "PoolName/[Solo]"` → Coinbase shows: `PoolName/[Solo]`
- `"btcsig": "/[Solo]"` → Coinbase shows: `/[Solo]`
- `"btcsig": ""` → No coinbase message

### Difficulty Configuration Examples

#### For Rental Services (NiceHash, MiningRigRentals)

```json
"mindiff_overrides": {
    "nicehash": 500000,           // Auto-detected via useragent OR worker name
    "NiceHash": 500000,           // Alternative capitalization
    "MiningRigRentals": 1000000,  // Auto-detected via useragent OR worker name
    "miningrigrentals": 1000000   // Alternative capitalization
}
```

**Note**: Rental services are **automatically detected** via useragent. The mindiff_overrides values are used as the difficulty to apply when detected.

#### For Custom Worker Groups

```json
"mindiff_overrides": {
    "bitaxe": 100,               // Low-power miners
    "s19": 1000000,              // Antminer S19 rigs
    "high": 5000000,             // High-performance farms
    "stratum-proxy": 10000       // Proxy connections
}
```

#### Password-Based Difficulty (Per Connection)

```bash
# Set specific difficulty via password
./cgminer -o stratum+tcp://pool:3333 -u BCH_ADDRESS.worker -p d=500000

# Or using long format
./bfgminer -o stratum+tcp://pool:3333 -u BCH_ADDRESS.worker -p diff=1000000

# Combine with other password options
./cgminer -o stratum+tcp://pool:3333 -u BCH_ADDRESS.worker -p d=500000,stats
```

### Complete Production Configuration

```json
{
    "btcd": [{
        "url": "127.0.0.1:8332",
        "auth": "rpcuser",
        "pass": "rpcpassword",
        "notify": true,
        "zmqnotify": "tcp://127.0.0.1:28333"
    }],
    "btcaddress": "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy",  // Main mining address
    "pooladdress": "bitcoincash:qp7azrnl28ezdvgnyjx3qmwfs8vph4jtxq9d7sdhez", // Pool fee address
    "poolfee": 1.0,                           // 1% pool fee
    "btcsig": "YourPool.com",                // Your pool branding
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": ["0.0.0.0:3333"],
    "mindiff": 500000,                        // ASIC optimized
    "startdiff": 500000,
    "maxdiff": 1000000,
    "mindiff_overrides": {                    // Per-pattern difficulty
        "nicehash": 500000,
        "MiningRigRentals": 1000000
    }
}
```

### Multi-Node Configuration (Recommended)

```json
{
    "btcd": [
        {
            "url": "10.0.1.10:8332",
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.10:28333"
        },
        {
            "url": "10.0.1.11:8332",
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.11:28333"
        }
    ],
    "btcaddress": "YOUR_BCH_ADDRESS",
    "btcsig": "EloPool.cloud",
    "pooladdress": "YOUR_BCH_ADDRESS",
    "poolfee": 1,
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "asicboost": true,
    "version_mask": "1fffe000"
}
```

## 🎯 NiceHash & MiningRigRentals Setup

### For Pool Operators

Just add to your config:
```json
{
    "mindiff_overrides": {
        "nicehash": 500000,
        "NiceHash": 500000,
        "MiningRigRentals": 1000000,
        "miningrigrentals": 1000000
    }
}
```

**That's it!** The pool will automatically detect and apply correct difficulty.

### For Miners/Renters

#### NiceHash
1. Add pool: `stratum+tcp://POOL_IP:3333`
2. Use your BCH address as username
3. Any password (or use `p=d=DIFFICULTY` to override)
4. **Pool auto-detects NiceHash and applies 500k+ difficulty**

#### MiningRigRentals
1. Pool URL: `stratum+tcp://POOL_IP:3333`
2. Worker: `YOUR_BCH_ADDRESS.rigname`
3. Password: `x` (or `d=DIFFICULTY` to set custom)
4. **Pool auto-detects MRR and applies 1M+ difficulty**

#### Regular Miners (Non-Rental)
```bash
# Use password to set your preferred difficulty
./cgminer -o stratum+tcp://POOL_IP:3333 -u BCH_ADDRESS.worker -p d=50000
```

## 🚦 BCH Node Setup

### Enable ZMQ in bitcoin.conf

```ini
# RPC Settings
rpcuser=yourusername
rpcpassword=yourpassword
rpcallowip=10.0.0.0/8
rpcbind=0.0.0.0

# ZMQ Settings (Required for fast block detection)
zmqpubhashblock=tcp://0.0.0.0:28333

# Mining Optimizations
maxmempool=2000
dbcache=4096
```

### Firewall Configuration

```bash
# On BCH nodes - allow ZMQ connections
sudo ufw allow 28333/tcp comment 'ZMQ block notifications'
sudo ufw allow from POOL_SERVER_IP to any port 8332 comment 'BCH RPC'

# On pool server - allow miner connections
sudo ufw allow 3333/tcp comment 'Stratum mining port'
```

## 🏃 Running the Pool

### Start the Pool

```bash
cd ~/ckpool
./start-ckpool.sh

# Or with systemd
sudo systemctl start ckpool
```

### Monitor Operations

```bash
# View logs
tail -f ~/ckpool/logs/ckpool.log

# Check statistics
./ckpmsg -s /tmp/ckpool/stratifier stats

# View connected workers
./ckpmsg -s /tmp/ckpool/stratifier users
```

### Stop the Pool

```bash
./stop-ckpool.sh

# Or with systemd
sudo systemctl stop ckpool
```

## 🔧 Troubleshooting

### ZMQ Connection Issues

1. **Check if ZMQ is enabled on BCH node:**
   ```bash
   bitcoin-cli getzmqnotifications
   ```

2. **Test ZMQ connectivity:**
   ```bash
   ./test-zmq-connection.sh
   ```

3. **Verify firewall rules:**
   ```bash
   sudo ufw status | grep 28333
   ```

### Performance Tuning

```bash
# Fix buffer size warnings
sudo ./tune-system.sh

# Increase system limits
ulimit -n 1048576
```

## 📊 API Commands

CKPool uses Unix sockets for administration:

```bash
# Pool statistics
./ckpmsg -s /tmp/ckpool/stratifier stats

# User information
./ckpmsg -s /tmp/ckpool/stratifier users

# Worker details
./ckpmsg -s /tmp/ckpool/stratifier workers

# Change log level
./ckpmsg -s /tmp/ckpool/pool loglevel=debug
```

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  BCH Node 1 │     │  BCH Node 2 │     │  BCH Node N │
│  RPC:8332   │     │  RPC:8332   │     │  RPC:8332   │
│  ZMQ:28333  │     │  ZMQ:28333  │     │  ZMQ:28333  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                    ┌──────┴──────┐
                    │   CKPool    │
                    │  Generator  │ ← Block Templates
                    │  Stratifier │ ← Share Validation
                    │  Connector  │ ← Client Connections
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │  Port 3333  │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
    │ ASIC 1  │      │ ASIC 2  │      │ ASIC N  │
    └─────────┘      └─────────┘      └─────────┘
```

## 📊 Testnet Achievements (September 2025)

### Successfully Mined Blocks
- **Block 1677517**: First CashAddr block
- **Block 1677523**: Confirmed CashAddr working
- **Block 1677558**: 1% pool fee distribution verified
- **Block 1677572**: 2% pool fee distribution verified
- **10+ additional blocks**: Continuous stable operation

### Verified Features
- ✅ CashAddr format (`bchtest:` addresses)
- ✅ Pool fee splitting (dual-output coinbase)
- ✅ Custom coinbase messages
- ✅ Low difficulty for Bitaxe miners
- ✅ Stable operation over extended periods

## 🚀 What's Different from Original CKPool?

This is not just a simple fork. EloPool has been extensively modified for Bitcoin Cash:

| Feature | Original CKPool | EloPool |
|---------|----------------|----------|
| **CashAddr Support** | ❌ None | ✅ Native implementation |
| **Pool Fee System** | ❌ Donation only | ✅ Configurable dual-output |
| **Difficulty Management** | Basic vardiff | 3 methods: Password, Useragent, Pattern |
| **Password Difficulty** | ❌ Not supported | ✅ `-p d=X` or `-p diff=X` |
| **Rental Detection** | ❌ Manual config | ✅ Auto-detect via useragent |
| **NiceHash Support** | ❌ Issues | ✅ Full compatibility |
| **MiningRigRentals** | ❌ Issues | ✅ Full compatibility |
| **BCH Optimizations** | ❌ BTC focused | ✅ BCH specific |
| **Coinbase Message** | Hardcoded "ckpool" | Fully configurable |
| **ZMQ Support** | Limited | Multi-node redundancy |

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly with BCH mainnet/testnet
4. Submit a pull request

## 📝 License

GNU Public License V3. See [COPYING](COPYING) for details.

## 🙏 Credits

- **Original CKPool**: Con Kolivas and the CKPool team (base architecture)
- **EloPool Development**:
  - CashAddr implementation (2025)
  - Pool fee system (2025)
  - Multi-difficulty enhancements (2025)
  - BCH-specific optimizations
- **Testing**: Successfully mining on BCH testnet since September 2025

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/skaisser/ckpool/issues)
- **Documentation**: [Wiki](https://github.com/skaisser/ckpool/wiki)

---

*EloPool - Production-ready Bitcoin Cash mining pool software with native CashAddr support*