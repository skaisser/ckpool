/*
 * Simplified CashAddr decoder for Bitcoin Cash
 * Based on asicseer-pool implementation approach
 * Focuses only on extracting hash160 from CashAddr format
 */

#define _GNU_SOURCE  /* For asprintf */
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include <stdio.h>
#include "libckpool.h"

/* CashAddr charset for base32 */
static const char CHARSET[] = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

static const int8_t CHARSET_REV[128] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    15, -1, 10, 17, 21, 20, 26, 30,  7,  5, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
     1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1
};

/* Polymod checksum calculation */
static uint64_t polymod(const uint8_t *values, size_t len)
{
    uint64_t c = 1;
    for (size_t i = 0; i < len; ++i) {
        uint8_t c0 = c >> 35;
        c = ((c & 0x07ffffffffULL) << 5) ^ values[i];
        
        if (c0 & 0x01) c ^= 0x98f2bc8e61ULL;
        if (c0 & 0x02) c ^= 0x79b76d99e2ULL;
        if (c0 & 0x04) c ^= 0xf33e5fb3c4ULL;
        if (c0 & 0x08) c ^= 0xae2eabe2a8ULL;
        if (c0 & 0x10) c ^= 0x1e4f43e470ULL;
    }
    return c;
}

/* Convert from 5-bit groups to 8-bit bytes */
static bool convert_bits_5to8(uint8_t *out, size_t *outlen, const uint8_t *in, size_t inlen)
{
    uint32_t acc = 0;
    int bits = 0;
    *outlen = 0;

    for (size_t i = 0; i < inlen; ++i) {
        uint8_t value = in[i];

        /* Each input value should be 0-31 (5 bits) */
        if (value >= 32) {
            return false;
        }

        acc = (acc << 5) | value;
        bits += 5;

        while (bits >= 8) {
            bits -= 8;
            out[(*outlen)++] = (acc >> bits) & 0xff;
        }
    }

    /* Check that any remaining bits are zero (proper padding) */
    if (bits >= 5 || (bits > 0 && ((acc << (8 - bits)) & 0xff) != 0)) {
        return false;
    }

    return true;
}

/* Extract hash160 from CashAddr - simplified version */
bool cashaddr_decode_simple(const char *addr, uint8_t *hash160, bool *is_p2sh)
{
    if (!addr || !hash160 || !is_p2sh) return false;
    
    /* Find the separator */
    const char *sep = strchr(addr, ':');
    const char *payload;
    size_t prefix_len;
    
    if (sep) {
        prefix_len = sep - addr;
        payload = sep + 1;
    } else {
        /* No prefix, assume it's just the payload */
        payload = addr;
        prefix_len = 0;
    }
    
    /* Decode the payload */
    size_t payload_len = strlen(payload);
    if (payload_len < 14 || payload_len > 112) {
        LOGDEBUG("Invalid payload length: %zu", payload_len);
        return false;
    }
    
    uint8_t data[112];
    size_t data_len = 0;
    
    /* Convert charset to values */
    for (size_t i = 0; i < payload_len; ++i) {
        int8_t value = CHARSET_REV[(uint8_t)tolower(payload[i])];
        if (value < 0) {
            LOGDEBUG("Invalid character in payload: %c", payload[i]);
            return false;
        }
        data[data_len++] = value;
    }
    
    /* The last 8 characters are checksum (40 bits) */
    if (data_len < 9) {  /* At least version + 1 byte payload + 8 checksum */
        LOGDEBUG("Payload too short for checksum");
        return false;
    }

    /* Remove checksum from the end */
    size_t data_without_checksum_len = data_len - 8;

    /* Convert from 5-bit to 8-bit */
    uint8_t decoded[65];
    size_t decoded_len;

    if (!convert_bits_5to8(decoded, &decoded_len, data, data_without_checksum_len)) {
        LOGDEBUG("Failed to convert from 5-bit to 8-bit");
        return false;
    }

    /* First byte is version/type byte */
    if (decoded_len < 21) {  /* version + 20 bytes hash */
        LOGDEBUG("Decoded length too short: %zu (expected at least 21)", decoded_len);
        return false;
    }

    /* Extract version byte */
    uint8_t version = decoded[0];

    /* Version byte format for CashAddr:
     * Upper 4 bits: type (0 = P2PKH, 1 = P2SH)
     * Lower 4 bits: size encoding
     */
    uint8_t type = (version >> 3) & 0x1f;
    *is_p2sh = (type == 1);

    /* Verify we have exactly 20 bytes for hash160 */
    if (decoded_len != 21) {
        LOGDEBUG("Invalid decoded length: %zu (expected 21 for hash160)", decoded_len);
        return false;
    }

    /* Copy the hash160 (skip version byte) */
    memcpy(hash160, decoded + 1, 20);
    
    /* Log what we extracted */
    char hash_hex[41];
    __bin2hex(hash_hex, hash160, 20);
    LOGDEBUG("Extracted hash160: %s (P2SH: %s)", hash_hex, *is_p2sh ? "true" : "false");
    
    return true;
}

/* Build P2PKH script from hash160 */
int hash160_to_p2pkh_script(uint8_t *script, const uint8_t *hash160)
{
    script[0] = 0x76;  /* OP_DUP */
    script[1] = 0xa9;  /* OP_HASH160 */
    script[2] = 0x14;  /* Push 20 bytes */
    memcpy(&script[3], hash160, 20);
    script[23] = 0x88; /* OP_EQUALVERIFY */
    script[24] = 0xac; /* OP_CHECKSIG */
    return 25;
}

/* Build P2SH script from hash160 */
int hash160_to_p2sh_script(uint8_t *script, const uint8_t *hash160)
{
    script[0] = 0xa9;  /* OP_HASH160 */
    script[1] = 0x14;  /* Push 20 bytes */
    memcpy(&script[2], hash160, 20);
    script[22] = 0x87; /* OP_EQUAL */
    return 23;
}

/* Simple CashAddr to script converter */
int cashaddr_to_script(const char *addr, uint8_t *script)
{
    uint8_t hash160[20];
    bool is_p2sh;
    
    if (!cashaddr_decode_simple(addr, hash160, &is_p2sh)) {
        LOGWARNING("Failed to decode CashAddr: %s", addr);
        return 0;
    }
    
    if (is_p2sh) {
        return hash160_to_p2sh_script(script, hash160);
    } else {
        return hash160_to_p2pkh_script(script, hash160);
    }
}