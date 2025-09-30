/* Test program for CashAddr implementation */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "cashaddr.h"

void test_address(const char *addr, const char *expected_legacy) {
    printf("\n=====================================\n");
    printf("Testing: %s\n", addr);
    printf("Expected legacy: %s\n", expected_legacy);

    const char *prefix = NULL;
    if (strncasecmp(addr, "bitcoincash:", 12) == 0)
        prefix = "bitcoincash";
    else if (strncasecmp(addr, "bchtest:", 8) == 0)
        prefix = "bchtest";
    else if (strncasecmp(addr, "bchreg:", 7) == 0)
        prefix = "bchreg";

    uint8_t *hash160 = cashaddr_decode_hash160(addr, prefix);

    if (hash160) {
        printf("✓ Decoded successfully\n");
        printf("Hash160: ");
        for (int i = 0; i < 20; i++) {
            printf("%02x", hash160[i]);
        }
        printf("\n");

        /* Build P2PKH script */
        uint8_t script[25];
        script[0] = 0x76;  /* OP_DUP */
        script[1] = 0xa9;  /* OP_HASH160 */
        script[2] = 0x14;  /* Push 20 bytes */
        memcpy(&script[3], hash160, 20);
        script[23] = 0x88; /* OP_EQUALVERIFY */
        script[24] = 0xac; /* OP_CHECKSIG */

        printf("Script: ");
        for (int i = 0; i < 25; i++) {
            printf("%02x", script[i]);
        }
        printf("\n");

        free(hash160);
    } else {
        printf("✗ Failed to decode\n");
    }
}

int main(int argc, char **argv) {
    printf("CashAddr Implementation Test\n");
    printf("Using AsicSeer's Bitcoin Cash Node implementation\n");

    /* Run built-in self tests first */
    printf("\nRunning self-tests...\n");
    if (cashaddr_selftest()) {
        printf("✓ Self-tests passed\n");
    } else {
        printf("✗ Self-tests FAILED!\n");
        return 1;
    }

    if (argc > 1) {
        /* Test addresses provided on command line */
        for (int i = 1; i < argc; i++) {
            test_address(argv[i], "");
        }
    } else {
        /* Default test addresses */
        printf("\n=== DEFAULT TEST ADDRESSES ===\n");

        /* The problematic mainnet address from production */
        test_address("bitcoincash:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze",
                    "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS");

        test_address("bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",
                    "Pool fee address");

        /* Known working testnet address */
        test_address("bchtest:qz3ah8rh7juw3gsstsnce3fnyura3d34qc6qqtc3zs",
                    "Testnet address");
    }

    return 0;
}