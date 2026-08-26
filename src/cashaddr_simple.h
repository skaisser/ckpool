/*
 * Simplified CashAddr decoder for Bitcoin Cash
 * Focused on extracting hash160 for script generation
 */

#ifndef CASHADDR_SIMPLE_H
#define CASHADDR_SIMPLE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Decode a CashAddr, verifying its checksum and network prefix, and extract
 * hash160. expected_prefix is e.g. "bitcoincash", "bchtest" or "bchreg".
 *
 * A prefixed address ("foo:payload") is rejected unless "foo" matches
 * expected_prefix (case-insensitively). A prefixless address is checksummed
 * directly against expected_prefix -- since the prefix participates in the
 * CashAddr checksum, an address meant for another network fails to
 * checksum-validate and is rejected.
 *
 * The address (prefix + payload together) must be either all-lowercase or
 * all-uppercase; mixed case is rejected.
 *
 * The version byte's reserved high bit (0x80) must be zero and the type
 * (bits 3-6) must be P2PKH (0) or P2SH (1); anything else is rejected. Only
 * hash160-sized (20 byte) payloads are supported.
 *
 * Returns true and fills hash160/is_p2sh only on a fully valid address. */
bool cashaddr_decode_checked(const char *addr, const char *expected_prefix,
			      uint8_t *hash160, bool *is_p2sh);

/* Decode CashAddr and extract hash160, defaulting to the mainnet
 * "bitcoincash" prefix. Thin wrapper over cashaddr_decode_checked() kept for
 * existing callers. */
bool cashaddr_decode_simple(const char *addr, uint8_t *hash160, bool *is_p2sh);

/* Convert hash160 to P2PKH script */
int hash160_to_p2pkh_script(uint8_t *script, const uint8_t *hash160);

/* Convert hash160 to P2SH script */
int hash160_to_p2sh_script(uint8_t *script, const uint8_t *hash160);

/* Direct CashAddr to script conversion */
int cashaddr_to_script(const char *addr, uint8_t *script);

#endif /* CASHADDR_SIMPLE_H */