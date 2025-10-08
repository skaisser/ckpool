# EloPool - Production-Ready Bitcoin Cash Mining Pool Software

**EloPool** is a heavily enhanced fork of CKPool, specifically optimized for Bitcoin Cash (BCH) mining. This production-ready pool software includes native CashAddr support, pool operator fee distribution, multi-difficulty management, and enterprise-grade reliability features.

## 🚀 What's Different from Original CKPool?

This is not just a simple fork. EloPool has been **extensively modified** for Bitcoin Cash:

| Feature | Original CKPool | EloPool |
|---------|----------------|----------|
| **CashAddr Support** | ❌ None | ✅ Native implementation |
| **Pool Fee System** | ❌ Donation only | ✅ Configurable dual-output |
| **Node Failover** | ❌ Slow (40+ failures) | ✅ **Instant (<100ms)** |
| **Sync-Aware Failover** | ❌ No | ✅ **Stays on backup during sync** |
| **Difficulty Management** | Basic vardiff | 3 methods: Password, Useragent, Pattern |
| **Password Difficulty** | ❌ Not supported | ✅ `-p d=X` or `-p diff=X` |
| **Rental Detection** | ❌ Manual config | ✅ Auto-detect via useragent |
| **NiceHash Support** | ❌ Issues | ✅ Full compatibility |
| **MiningRigRentals** | ❌ Issues | ✅ Full compatibility |
| **Share Validation** | Rejects below target | Only rejects below mindiff |
| **BCH Optimizations** | ❌ BTC focused | ✅ BCH specific |
| **Coinbase Message** | Hardcoded "ckpool" | Fully configurable |
| **ZMQ Support** | Limited | Multi-node redundancy |

## 🏆 Production Achievements
- **66 Blocks mined on BCH mainnet** - Proven reliability in production
- **Successfully mining on BCH mainnet** since 2025
- **Battle-tested** with real ASIC hardware (Bitaxe, rental services)
- **Zero share rejections** - Smart validation accepts all valid work
- **Native CashAddr working** - Proven with millions of shares
- **Pool fees working** - Automatic 98/2% split in every block

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
  - Backwards compatible with legacy Base58 addresses
  - **Production Proven**: Successfully mining on mainnet and testnet

#### 3. **Advanced Multi-Difficulty Management** ✅

**Three Methods of Difficulty Control (Priority Order):**

##### a) **Password-Based Difficulty** (Highest Priority) ✅ TESTED
  - Set difficulty via password field: `-p d=500000` or `-p diff=1000000`
  - **Both formats supported**: `d=` (short) and `diff=` (long)
  - Overrides ALL other difficulty settings
  - Applied immediately upon authorization
  - Perfect for individual miner control
  - **Testnet verified**: Successfully tested with `d=41245` on Bitaxe
  - Examples:
    ```bash
    # Short format (tested & working)
    ./bfgminer -o stratum+tcp://pool:3333 -u wallet.worker -p d=500000

    # Long format (also supported)
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

#### 4. **Enterprise-Grade Multi-Node Redundancy** ✅
  - **Instant failover** - Switches to backup on first RPC failure (~100ms)
  - **Intelligent node selection** - Prefers primary, automatically fails back when recovered
  - **Sync-aware** - Stays on backup while primary node is syncing/loading
  - **Zero mining downtime** - Continuous operation during node maintenance
  - **Multi-node ZMQ** - Receives block notifications from all nodes
  - **Production proven** - Handles node restarts gracefully

  **Failover Performance:**
  - Old behavior: 40+ failed attempts before failover (4+ seconds)
  - **New behavior: 1 failed attempt, instant failover** (<100ms)
  - Automatic recovery detection every 5 seconds
  - Seamless failback when primary node is ready

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

### Quick Install (Production - Recommended)

```bash
# 1. Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# 2. Install dependencies and build
./install-ckpool.sh

# 3. Configure your pool settings
nano ~/ckpool/ckpool.conf
# Edit: btcaddress, pooladdress, poolfee, btcd credentials

# 4. Set up systemd service and firewall (requires sudo)
sudo ./post-install.sh
```

**What each script does:**

- **`install-ckpool.sh`** - Checks dependencies, builds CKPool, creates configs
- **`post-install.sh`** - Creates systemd service, configures firewall, enables auto-start

### Manual Install (Development/Testing)

```bash
# Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# Build and install
./autogen.sh
./configure
make
sudo make install
```

**Note:** Manual install does not create systemd service or configure firewall. You'll need to run `post-install.sh` separately or manage the service manually.

## ⚙️ Configuration

### Pool Operator Fee Configuration

```json
{
    // Mainnet example with CashAddr:
    "btcaddress": "bitcoincash:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze",  // Miner receives 99%
    "pooladdress": "bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w", // Pool receives 1%

    // Legacy addresses also work:
    // "btcaddress": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
    // "pooladdress": "1PeURBa2vVBuKgeqRjVNqF7eGumeZCJ3mb",

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
    "btcaddress": "bitcoincash:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze",  // Main mining address
    "pooladdress": "bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",  // Pool fee address
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

### Multi-Node Configuration (Highly Recommended for Production)

**Why Multi-Node?**
- **Zero downtime** during node maintenance or updates
- **Instant failover** on node failure (<100ms switching time)
- **Automatic recovery** when primary node comes back online
- **Production-grade reliability** - no single point of failure

```json
{
    "btcd": [
        {
            "url": "10.0.1.10:8332",      // Primary node
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.10:28333"
        },
        {
            "url": "10.0.1.11:8332",      // Backup node
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.11:28333"
        }
    ],
    "btcaddress": "YOUR_BCH_ADDRESS",  // CashAddr or legacy format
    "btcsig": "EloPool.cloud",
    "pooladdress": "YOUR_BCH_FEE_ADDRESS", // CashAddr or legacy format
    "poolfee": 1,
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "asicboost": true,
    "version_mask": "1fffe000"
}
```

**Node Priority:**
- First node in array = Primary (always preferred when available)
- Subsequent nodes = Backup (used during primary failure/maintenance)
- Pool automatically fails back to primary when it recovers

**Example Failover Behavior:**

```log
# Startup - Both nodes detected
[18:24:02.087] Connected to bitcoind: 10.12.112.3:8332
[18:24:02.088] Server alive: 10.12.112.3:8332
[18:24:02.090] Server alive: 10.12.112.4:8332

# Primary node goes down - Instant failover (1 failure, <100ms)
[18:25:27.454] Unable to connect socket to 10.12.112.3:8332
[18:25:27.454] Failed to get best block hash from 10.12.112.3:8332
[18:25:27.454] Failed over to bitcoind: 10.12.112.4:8332  ← INSTANT

# Mining continues on backup without interruption
[18:25:32.151] Stored local workbase with 24 transactions

# Primary comes back but still syncing - Pool stays on backup
[18:26:07.112] "Loading block index..." (node not ready yet)
[18:26:07.112] 10.12.112.3:8332 Failed to get valid json response

# Primary fully synced - Automatic failback (5 seconds later)
[18:26:12.114] Server alive: 10.12.112.3:8332
[18:26:12.115] Failed over to bitcoind: 10.12.112.3:8332  ← Back to primary

# Continues mining on primary
[18:26:32.453] Stored local workbase with 29 transactions
```

**Key Behaviors:**
- ✅ **Single failure triggers failover** (not 40+ like before)
- ✅ **Stays on backup during primary sync** (sync-aware)
- ✅ **Automatic failback when ready** (intelligent recovery)
- ✅ **Zero share loss** during failover
- ✅ **Miners never disconnected** (seamless transition)

## 🎯 NiceHash & MiningRigRentals Setup

### ✅ Production Tested & Verified
- ✅ **Password-based difficulty**: Tested & working in production
- ✅ **Useragent detection**: Tested & working with NiceHash
- ✅ **Pattern matching**: Tested & working in production

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

#### NiceHash (Ready for Production Testing)
1. Add pool: `stratum+tcp://POOL_IP:3333`
2. Use your BCH address as username
3. Any password (or use `d=DIFFICULTY` to override)
4. **Pool auto-detects NiceHash from useragent and applies 500k+ difficulty**
5. **Note**: Ensure `maxdiff` is 0 or > 500000 in config

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

### Option 1: Systemd Service (Recommended for Production)

After running `post-install.sh`, manage the pool as a system service:

```bash
# Start the pool
sudo systemctl start ckpool

# Stop the pool
sudo systemctl stop ckpool

# Restart the pool
sudo systemctl restart ckpool

# Check status
sudo systemctl status ckpool

# View live logs
sudo journalctl -u ckpool -f

# Enable auto-start on boot
sudo systemctl enable ckpool

# Disable auto-start
sudo systemctl disable ckpool
```

**Testnet Service:**
```bash
# Same commands but replace 'ckpool' with 'ckpool-testnet'
sudo systemctl start ckpool-testnet
sudo journalctl -u ckpool-testnet -f
```

### Option 2: Manual Scripts (Testing/Development)

```bash
# Start the pool
cd ~/ckpool
./start-ckpool.sh

# Stop the pool
./stop-ckpool.sh

# View logs
tail -f ~/ckpool/logs/ckpool.log
```

### Monitor Operations

```bash
# Pool statistics
./ckpmsg -s /tmp/ckpool/stratifier stats

# User information
./ckpmsg -s /tmp/ckpool/stratifier users

# Worker details
./ckpmsg -s /tmp/ckpool/stratifier workers

# View logs (systemd)
sudo journalctl -u ckpool -f --lines=100

# View logs (manual)
tail -f ~/ckpool/logs/ckpool.log
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
- ✅ Password-based difficulty (`-p d=41245` tested with Bitaxe)
- ✅ Low difficulty for Bitaxe miners
- ✅ Stable operation over extended periods

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