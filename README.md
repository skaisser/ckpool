# EloPool (CKPool Fork) - High-Performance Bitcoin Cash Mining Pool

**EloPool** is an enhanced fork of CKPool optimized for Bitcoin Cash (BCH) mining with enterprise-grade features including multi-node ZMQ support, ASIC optimization, and high-performance architecture.

## 🚀 Key Features

### Core CKPool Features
- **Ultra-low overhead** massively scalable multi-process, multi-threaded architecture
- **Multiple deployment modes**: Pool, Solo, Proxy, Passthrough, Node
- **Seamless restarts** with socket handover for zero-downtime upgrades
- **ASICBoost support** for improved mining efficiency
- **Advanced vardiff** algorithm with stable high-difficulty handling

### EloPool Enhancements
- **Multi-Node ZMQ Support** 🆕
  - Connect to multiple BCH nodes simultaneously
  - Redundant block notifications (failover support)
  - Faster block detection (milliseconds vs polling)
  - Load distribution across nodes
- **Multi-Difficulty Support** 🆕
  - Single port operation with per-miner difficulty
  - Password-based difficulty setting (`-p d=1000` or `-p diff=1000000`)
  - Automatic difficulty for rental services via mindiff_overrides
  - Pattern-based worker name matching
- **Bitcoin Cash CashAddr Support** ✅
  - Full CashAddr address format support (no external dependencies)
  - Supports `bitcoincash:`, `bchtest:`, `bchreg:` prefixes
  - Native 5-bit to 8-bit conversion and checksum verification
  - Backward compatible with legacy Base58 addresses
  - **Successfully tested on BCH testnet** - Blocks 1677517, 1677523 mined to `bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs` ✓
- **Bitcoin Cash Optimizations**
  - SegWit removed for BCH compatibility
  - Optimized for ASIC miners (500k+ difficulty)
  - Fully configurable coinbase signatures (no hardcoded text)
- **Production-Ready Configuration**
  - Pre-configured for high-performance ASIC mining
  - Comprehensive logging and monitoring
  - SystemD service integration

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

### Coinbase Message (btcsig)

The `btcsig` parameter controls the **entire** coinbase message that appears in mined blocks. There is no hardcoded text - whatever you set in `btcsig` is exactly what will appear in the blockchain.

**Examples:**
- `"btcsig": "MyPool.com"` → Coinbase shows: `MyPool.com`
- `"btcsig": "PoolName/[Solo]"` → Coinbase shows: `PoolName/[Solo]`
- `"btcsig": "/[Solo]"` → Coinbase shows: `/[Solo]`
- `"btcsig": ""` → No coinbase message

### Multi-Difficulty Settings

Configure automatic difficulty per worker pattern using `mindiff_overrides`:

```json
"mindiff_overrides": {
    "nicehash": 500000,      // Workers with "nicehash" in name
    "MiningRigRentals": 1000000,  // Mining rental services
    "bitaxe": 1000,          // Low-power miners
    "stratum-proxy": 10000   // Proxy connections
}
```

Miners can also set difficulty via password:
- `-p d=1000` - Short format
- `-p diff=1000000` - Long format
- Password difficulty overrides all other settings

### Basic Configuration (Single Node)

```json
{
    "btcd": [{
        "url": "127.0.0.1:8332",
        "auth": "rpcuser",
        "pass": "rpcpassword",
        "notify": true,
        "zmqnotify": "tcp://127.0.0.1:28333"
    }],
    "btcaddress": "YOUR_BCH_ADDRESS",
    "btcsig": "PoolName/[Solo]",
    "pooladdress": "YOUR_BCH_ADDRESS",
    "poolfee": 1,
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": ["0.0.0.0:3333"],
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000
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

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly with BCH mainnet/testnet
4. Submit a pull request

## 📝 License

GNU Public License V3. See [COPYING](COPYING) for details.

## 🙏 Credits

- **Original CKPool**: Con Kolivas and the CKPool team
- **EloPool Fork**: Enhanced for Bitcoin Cash by the EloPool team
- **Multi-Node ZMQ**: Implemented for enterprise BCH mining operations

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/skaisser/ckpool/issues)
- **Documentation**: [Wiki](https://github.com/skaisser/ckpool/wiki)

---

*EloPool - Enterprise-grade Bitcoin Cash mining pool software*