#!/bin/bash

# This script removes the old separate test scripts
# Now replaced by test-ckpool-regtest.sh

echo "The following scripts are deprecated and replaced by test-ckpool-regtest.sh:"
echo "  - setup-bch-regtest.sh"
echo "  - testckpool.sh"
echo
echo "The new unified script handles everything safely:"
echo "  ./test-ckpool-regtest.sh      # Start regtest environment"
echo "  ./test-ckpool-regtest.sh stop # Stop regtest environment"
echo
read -p "Remove deprecated scripts? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f setup-bch-regtest.sh testckpool.sh
    echo "✅ Removed deprecated scripts"
else
    echo "Keeping old scripts"
fi