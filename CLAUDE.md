# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CKPool (rebranded as EloPool) is a high-performance Bitcoin Cash (BCH) mining pool written in C. It uses a modular multi-process architecture with Unix domain sockets for IPC, optimized for ASIC miners with production-ready features like seamless restarts and comprehensive monitoring.

## Build and Development Commands

### Building the Project
```bash
# Clean build from scratch
./clean-build.sh

# Standard build process
./autogen.sh      # Generate configure script
./configure       # Configure with hardware optimizations
make             # Build all components

# Installation
./install-ckpool.sh                          # Production install to ~/ckpool
./production-scripts/install-ckpool-test.sh  # Test install to ~/ckpool-test
```

### Running and Testing
```bash
# Start pool (production)
~/ckpool/ckpool -c ~/ckpool/ckpool.conf

# Start pool (solo mode)
~/ckpool/ckpool -B -c ~/ckpool/ckpool.conf

# Complete regtest environment with miner
./production-scripts/test-ckpool-regtest.sh

# Generate test transactions
./production-scripts/generate-regtest-transactions.sh

# Test mining connectivity
./testing/minerd -a sha256d -o 127.0.0.1:3334 -u myworker -p x --no-longpoll --no-getwork --no-stratum
```

### Administration and Monitoring
```bash
# Using ckpmsg for pool administration (Unix sockets)
ckpmsg -s /tmp/ckpool/stratifier stats        # Pool statistics
ckpmsg -s /tmp/ckpool/stratifier users        # All users
ckpmsg -s /tmp/ckpool/stratifier workers      # All workers
ckpmsg -s /tmp/ckpool/stratifier user.info=USERNAME
ckpmsg -s /tmp/ckpool/stratifier worker.info=WORKERNAME
ckpmsg -s /tmp/ckpool/pool loglevel=debug     # Change log level
```

## Architecture and Code Structure

### Core Process Architecture
The pool uses a 4-process architecture communicating via Unix domain sockets:

1. **Main Process** (`src/ckpool.c`) - Coordinator, configuration, process management
2. **Stratifier** (`src/stratifier.c`) - Mining protocol, share validation, user management, difficulty adjustment
3. **Generator** (`src/generator.c`) - Bitcoin Cash daemon interface, block template generation
4. **Connector** (`src/connector.c`) - Client connections, network I/O, protocol handling

### Key Source Files
- `src/libckpool.c/.h` - Shared library functions, utilities, socket handling
- `src/ckpmsg.c` - Administration tool for Unix socket communication
- `src/notifier.c` - Block notification handler for bitcoind ZMQ
- `src/sha256_*.c` - Hardware-optimized SHA256 implementations (AVX2, AVX1, SSE4, ARM)

### Configuration System
- JSON-based configuration files (using embedded jansson library)
- Main config: `ckpool.conf` with BCH-specific settings
- Operating modes: pool, solo (`-B`), proxy (`-p`), passthrough (`-P`), node (`-N`), redirector (`-R`)
- Production defaults: 500k-1M difficulty for ASIC miners

### Bitcoin Cash Adaptations
- SegWit removed from `getblocktemplate` calls
- Coinbase signature: "EloPool.cloud/[Solo]" 
- BCH-specific difficulty and block validation
- ASICBoost support for mining efficiency

### Testing Infrastructure
- `testing/minerd` - CPU miner for connectivity tests
- `production-scripts/test-ckpool-regtest.sh` - Complete regtest environment
- `test/` directory - SHA256 validation tests
- Regtest configuration with automated block generation

## Development Guidelines

### Code Conventions
- C99 standard with GNU extensions
- Error handling via `LOGERR`, `LOGWARNING`, `LOGINFO` macros
- Memory management with custom allocators (`ckalloc`, `ckfree`)
- Thread-safe operations using pthread primitives
- Event-driven architecture with epoll/select

### Making Changes
- Stratifier modifications affect mining protocol and shares
- Generator changes impact bitcoind communication
- Connector modifications affect client handling
- Always test with regtest before production

### Building After Changes
```bash
make clean && make                    # Rebuild after C code changes
./clean-build.sh && ./autogen.sh && ./configure && make  # Full rebuild
```

### Debugging
- Use `loglevel` command via ckpmsg to increase verbosity
- Check `/tmp/ckpool/*.log` for process-specific logs
- Use `gdb` with core dumps enabled for crash debugging
- Test with minerd for protocol verification

## Important Notes

- **Unix Sockets Only**: No HTTP API - all administration via ckpmsg and Unix sockets
- **Production Settings**: Default configs optimized for ASIC miners (500k+ difficulty)
- **BCH Specific**: This fork is for Bitcoin Cash only, not Bitcoin Core
- **Process Isolation**: Each component runs as separate process for stability
- **Seamless Restarts**: Socket handover allows zero-downtime updates