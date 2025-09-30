#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "src/cashaddr_simple.h"

void test_cashaddr_decode(const char *addr_str) {
    uint8_t hash160[20];
    bool is_p2sh;

    printf("\nTesting: %s\n", addr_str);

    bool result = cashaddr_decode_simple(addr_str, hash160, &is_p2sh);

    if (result) {
        printf("  ✓ Decoded successfully\n");
        printf("  Type: %s\n", is_p2sh ? "P2SH" : "P2PKH");
        printf("  Hash160: ");
        for (int i = 0; i < 20; i++) {
            printf("%02x", hash160[i]);
        }
        printf("\n");
    } else {
        printf("  ✗ Failed to decode\n");
    }
}

int main() {
    printf("CashAddr Support Test\n");
    printf("=====================\n");

    // Test mainnet address
    test_cashaddr_decode("bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy");

    // Test testnet address
    test_cashaddr_decode("bchtest:qpvvcah8gzn7kz04jzamet8q2vv8uat9fqvhuy25gm");

    // Test regtest address
    test_cashaddr_decode("bchreg:qpttdv3qg2usm4nm7talhxhl05mlhms3ys43u76rn0");

    // Test invalid address
    test_cashaddr_decode("bitcoincash:invalid123");

    printf("\nAll tests completed.\n");
    return 0;
}