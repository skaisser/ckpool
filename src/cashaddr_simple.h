/*
 * Simplified CashAddr decoder for Bitcoin Cash
 * Focused on extracting hash160 for script generation
 */

#ifndef CASHADDR_SIMPLE_H
#define CASHADDR_SIMPLE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Decode CashAddr and extract hash160 */
bool cashaddr_decode_simple(const char *addr, uint8_t *hash160, bool *is_p2sh);

/* Convert hash160 to P2PKH script */
int hash160_to_p2pkh_script(uint8_t *script, const uint8_t *hash160);

/* Convert hash160 to P2SH script */
int hash160_to_p2sh_script(uint8_t *script, const uint8_t *hash160);

/* Direct CashAddr to script conversion */
int cashaddr_to_script(const char *addr, uint8_t *script);

#endif /* CASHADDR_SIMPLE_H */