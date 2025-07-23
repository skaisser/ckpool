# Testing Tools

This folder contains tools for testing CKPool functionality.

## minerd

A CPU miner for testing pool connectivity and mining operations.

### Usage
```bash
./minerd -a sha256d -o stratum+tcp://localhost:3333 -u username.worker -p x --coinbase-addr=<BCH_ADDRESS>
```

### Options
- `-a sha256d` - Use SHA256d algorithm (for Bitcoin Cash)
- `-o` - Pool URL (stratum+tcp://host:port)
- `-u` - Username.workername
- `-p` - Password (usually 'x' for most pools)
- `--coinbase-addr` - BCH address for solo mining

### Example for Testing
```bash
# For regtest
./minerd -a sha256d -o stratum+tcp://localhost:3333 -u skaisser.test -p x --coinbase-addr=bchreg:qqugw9vuyndj3wd8ewuxll8zs29j96mh3v93fxhygd

# For mainnet
./minerd -a sha256d -o stratum+tcp://localhost:3333 -u skaisser.rig1 -p x
```

### Notes
- This is a pre-compiled binary (64-bit Linux)
- Only depends on standard system libraries
- No need to recompile unless changing architectures
- Mainly used for testing, not efficient for actual mining