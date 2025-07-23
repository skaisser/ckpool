# Production Scripts

This folder contains useful scripts and configurations for testing and deploying CKPool.

## Contents

### Installation Scripts
- `install-ckpool-test.sh` - Install CKPool in test mode (separate from production)

### Test Scripts
- `test-ckpool-regtest.sh` - Complete Bitcoin Cash regtest environment setup and testing
- `test-mine-block.sh` - Simple block mining test script
- `testckpool.sh` - Basic CKPool functionality test
- `generate-regtest-transactions.sh` - Generate transactions for realistic test environment

### Utility Scripts
- `cleanup-regtest.sh` - Clean up all test artifacts and installations
- `verify-pool-coinbase.sh` - Verify coinbase message configuration
- `rebuild-ckpool-test.sh` - Rebuild test installation after code changes

### Configuration Examples
- `ckpool-regtest.conf.example` - Example configuration for regtest network

## Usage

### For Testing
1. Use `install-ckpool-test.sh` to set up a test environment in `~/ckpool-test`
2. Use `test-ckpool-regtest.sh` to run a complete regtest environment
3. Use `test-mine-block.sh` for quick mining tests

### For Production
1. Use the main `install-ckpool.sh` script in the parent directory
2. Refer to configuration examples for setup guidance

## Notes
- Test scripts use regtest network (not real Bitcoin Cash)
- Production installer includes EloPool branding instead of ckpool
- All test installations go to `~/ckpool-test` to avoid conflicts