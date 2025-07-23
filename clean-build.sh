#!/bin/bash

# Clean all build artifacts from CKPool source directory
# Use this if you accidentally ran 'make' instead of install script

echo "Cleaning CKPool build artifacts..."

# Remove binaries from root
rm -f ckpool ckpmsg notifier test-driver 2>/dev/null

# Remove build artifacts
rm -f src/libckpool.a src/notifier 2>/dev/null
rm -f test/sha256 2>/dev/null

# Remove jansson build files
rm -f src/jansson-2.14/jansson.pc 2>/dev/null
rm -f src/jansson-2.14/jansson_private_config.h 2>/dev/null
rm -f src/jansson-2.14/src/jansson_config.h 2>/dev/null

# Remove service files
rm -f ckpool-regtest.service 2>/dev/null

# Run make clean if available
if [ -f Makefile ]; then
    echo "Running make clean..."
    make clean 2>/dev/null || true
fi

echo "✓ Build artifacts cleaned"
echo
echo "To build and install properly, use:"
echo "  ./install-ckpool.sh        # For production"
echo "  ./install-ckpool-test.sh   # For testing"