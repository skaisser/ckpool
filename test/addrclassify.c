/*
 * Standalone native test for the BCH address classifier
 * (bch_classify_address()/bch_address_to_script()/address_to_txn(), all in
 * src/libckpool.c) and its interaction with the CashAddr decoder
 * (src/cashaddr_simple.c).
 *
 * Unlike test/cashaddr.c this links the REAL production classifier code
 * (src/libckpool.c compiled as its own object, not libckpool.a) together
 * with src/cashaddr_simple.c and src/sha2.c, so it exercises the exact
 * validate/construct path the pool uses. libckpool.c pulls in a handful of
 * jansson entry points for code paths this test never reaches (RPC/JSON
 * helpers); weak stubs below satisfy the linker without needing to build
 * jansson itself.
 *
 * Ground truth for legacy (Base58Check) vectors is derived at runtime from
 * a tiny local base58 decoder + SHA256 implementation, independent of the
 * production decoder, so the test does not depend on transcribing hash160
 * hex by hand. Ground truth for CashAddr vectors reuses the
 * cashaddr/legacy address pairs already proven correct by the Phase 1
 * suite (test/cashaddr.c), cross-checked against that same local decoder.
 * A local independent CashAddr encoder (synth_cashaddr, mirroring
 * test/cashaddr.c) synthesizes genuinely-valid non-mainnet vectors.
 */

#include "config.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "libckpool.h"
#include "cashaddr_simple.h"

/* ---- weak stubs for jansson entry points libckpool.c references but
 * this test never exercises (RPC/JSON code paths) ---- */
#if defined(__GNUC__) || defined(__clang__)
#define WEAK_SYM __attribute__((weak))
#else
#define WEAK_SYM
#endif

WEAK_SYM json_t *json_array_get(const json_t *array, size_t index)
{
	(void)array;
	(void)index;
	return NULL;
}

WEAK_SYM size_t json_array_size(const json_t *array)
{
	(void)array;
	return 0;
}

WEAK_SYM json_t *json_copy(json_t *value)
{
	(void)value;
	return NULL;
}

WEAK_SYM json_t *json_object_get(const json_t *object, const char *key)
{
	(void)object;
	(void)key;
	return NULL;
}

WEAK_SYM const char *json_string_value(const json_t *json)
{
	(void)json;
	return NULL;
}

/* ------------------------------ SHA256 ----------------------------------
 * Public-domain style minimal SHA256, independent of src/sha2.c, used only
 * to verify base58check checksums of the legacy test vectors below.
 */

typedef struct {
	uint8_t data[64];
	uint32_t datalen;
	uint64_t bitlen;
	uint32_t state[8];
} SHA256_CTX;

#define ROTRIGHT(a, b) (((a) >> (b)) | ((a) << (32 - (b))))
#define CH(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x, 2) ^ ROTRIGHT(x, 13) ^ ROTRIGHT(x, 22))
#define EP1(x) (ROTRIGHT(x, 6) ^ ROTRIGHT(x, 11) ^ ROTRIGHT(x, 25))
#define SIG0(x) (ROTRIGHT(x, 7) ^ ROTRIGHT(x, 18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x, 17) ^ ROTRIGHT(x, 19) ^ ((x) >> 10))

static const uint32_t local_sha256_k[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static void local_sha256_transform(SHA256_CTX *ctx, const uint8_t data[])
{
	uint32_t a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

	for (i = 0, j = 0; i < 16; ++i, j += 4)
		m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) |
		       ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
	for ( ; i < 64; ++i)
		m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];

	a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
	e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

	for (i = 0; i < 64; ++i) {
		t1 = h + EP1(e) + CH(e, f, g) + local_sha256_k[i] + m[i];
		t2 = EP0(a) + MAJ(a, b, c);
		h = g; g = f; f = e; e = d + t1;
		d = c; c = b; b = a; a = t1 + t2;
	}

	ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
	ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void local_sha256_init(SHA256_CTX *ctx)
{
	ctx->datalen = 0;
	ctx->bitlen = 0;
	ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
	ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
	ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
	ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void local_sha256_update(SHA256_CTX *ctx, const uint8_t data[], size_t len)
{
	size_t i;

	for (i = 0; i < len; ++i) {
		ctx->data[ctx->datalen] = data[i];
		ctx->datalen++;
		if (ctx->datalen == 64) {
			local_sha256_transform(ctx, ctx->data);
			ctx->bitlen += 512;
			ctx->datalen = 0;
		}
	}
}

static void local_sha256_final(SHA256_CTX *ctx, uint8_t hash[32])
{
	uint32_t i = ctx->datalen;

	if (ctx->datalen < 56) {
		ctx->data[i++] = 0x80;
		while (i < 56)
			ctx->data[i++] = 0x00;
	} else {
		ctx->data[i++] = 0x80;
		while (i < 64)
			ctx->data[i++] = 0x00;
		local_sha256_transform(ctx, ctx->data);
		memset(ctx->data, 0, 56);
	}

	ctx->bitlen += (uint64_t)ctx->datalen * 8;
	ctx->data[63] = (uint8_t)(ctx->bitlen);
	ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
	ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
	ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
	ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
	ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
	ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
	ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
	local_sha256_transform(ctx, ctx->data);

	for (i = 0; i < 4; ++i) {
		hash[i]      = (ctx->state[0] >> (24 - i * 8)) & 0xff;
		hash[i + 4]  = (ctx->state[1] >> (24 - i * 8)) & 0xff;
		hash[i + 8]  = (ctx->state[2] >> (24 - i * 8)) & 0xff;
		hash[i + 12] = (ctx->state[3] >> (24 - i * 8)) & 0xff;
		hash[i + 16] = (ctx->state[4] >> (24 - i * 8)) & 0xff;
		hash[i + 20] = (ctx->state[5] >> (24 - i * 8)) & 0xff;
		hash[i + 24] = (ctx->state[6] >> (24 - i * 8)) & 0xff;
		hash[i + 28] = (ctx->state[7] >> (24 - i * 8)) & 0xff;
	}
}

static void local_sha256_once(const uint8_t *data, size_t len, uint8_t out[32])
{
	SHA256_CTX ctx;

	local_sha256_init(&ctx);
	local_sha256_update(&ctx, data, len);
	local_sha256_final(&ctx, out);
}

/* --------------------------- base58check -------------------------------
 * Decodes a legacy address into its 25-byte payload (version + hash160 +
 * checksum), verifying the double-SHA256 checksum. Independent of
 * bch_b58decode_strict() in src/libckpool.c. Used only to derive
 * ground-truth hash160/version for the legacy vectors below.
 */

static bool local_base58_decode_25(const char *s, uint8_t out25[25])
{
	static const char *ALPHA = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
	size_t len = strlen(s);
	size_t i;

	memset(out25, 0, 25);
	for (i = 0; i < len; ++i) {
		const char *p = strchr(ALPHA, s[i]);
		int carry;
		int j;

		if (!p || s[i] == '\0')
			return false;
		carry = (int)(p - ALPHA);
		for (j = 24; j >= 0; --j) {
			carry += 58 * out25[j];
			out25[j] = carry & 0xff;
			carry >>= 8;
		}
		if (carry)
			return false; /* overflow: not a 25-byte legacy address */
	}
	return true;
}

/* Decode addr and verify its checksum, filling hash160/version on
 * success. Does not care what the version byte means -- callers check
 * that. */
static bool local_legacy_decode(const char *addr, uint8_t hash160[20], uint8_t *version)
{
	uint8_t decoded[25], chk1[32], chk2[32];

	if (!local_base58_decode_25(addr, decoded))
		return false;

	local_sha256_once(decoded, 21, chk1);
	local_sha256_once(chk1, 32, chk2);
	if (memcmp(chk2, decoded + 21, 4) != 0)
		return false;

	*version = decoded[0];
	memcpy(hash160, decoded + 1, 20);
	return true;
}

/* --------------------- mini independent CashAddr encoder -----------------
 * Synthesizes a genuinely valid, correctly-checksummed CashAddr for a
 * given prefix/version/hash160, so tests can construct non-mainnet
 * ("bchtest:"/"bchreg:") vectors and P2SH cashaddr vectors without
 * depending on the production encoder (there isn't one) or on
 * hand-transcribed strings. Deliberately not shared code with
 * cashaddr_simple.c.
 */

static const char TEST_CHARSET[] = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

static uint64_t ref_polymod(const uint8_t *v, size_t len)
{
	uint64_t c = 1;
	size_t i;

	for (i = 0; i < len; ++i) {
		uint8_t c0 = c >> 35;
		c = ((c & 0x07ffffffffULL) << 5) ^ v[i];
		if (c0 & 0x01) c ^= 0x98f2bc8e61ULL;
		if (c0 & 0x02) c ^= 0x79b76d99e2ULL;
		if (c0 & 0x04) c ^= 0xf33e5fb3c4ULL;
		if (c0 & 0x08) c ^= 0xae2eabe2a8ULL;
		if (c0 & 0x10) c ^= 0x1e4f43e470ULL;
	}
	return c ^ 1;
}

static bool synth_cashaddr(char *out, size_t outsz, const char *prefix,
			   uint8_t version, const uint8_t hash160[20])
{
	uint8_t payload8[21];
	uint8_t data5[40];
	size_t data5_len = 0;
	uint32_t acc = 0;
	int bits = 0;
	size_t i, prefix_len, idx, pos;
	uint8_t buf[1 + 20 + 40 + 8];
	uint64_t mod;
	uint8_t checksum[8];

	payload8[0] = version;
	memcpy(payload8 + 1, hash160, 20);

	for (i = 0; i < sizeof(payload8); ++i) {
		acc = (acc << 8) | payload8[i];
		bits += 8;
		while (bits >= 5) {
			bits -= 5;
			data5[data5_len++] = (acc >> bits) & 0x1f;
		}
	}
	if (bits > 0)
		data5[data5_len++] = (acc << (5 - bits)) & 0x1f;

	prefix_len = strlen(prefix);
	idx = 0;
	for (i = 0; i < prefix_len; ++i)
		buf[idx++] = ((uint8_t)prefix[i]) & 0x1f;
	buf[idx++] = 0;
	for (i = 0; i < data5_len; ++i)
		buf[idx++] = data5[i];
	for (i = 0; i < 8; ++i)
		buf[idx++] = 0;

	mod = ref_polymod(buf, idx);
	for (i = 0; i < 8; ++i)
		checksum[i] = (mod >> (5 * (7 - i))) & 0x1f;

	if (prefix_len + 1 + data5_len + 8 + 1 > outsz)
		return false;

	pos = 0;
	memcpy(out + pos, prefix, prefix_len); pos += prefix_len;
	out[pos++] = ':';
	for (i = 0; i < data5_len; ++i)
		out[pos++] = TEST_CHARSET[data5[i]];
	for (i = 0; i < 8; ++i)
		out[pos++] = TEST_CHARSET[checksum[i]];
	out[pos] = '\0';
	return true;
}

/* ------------------------------ harness --------------------------------- */

static int tests_run = 0, tests_failed = 0;

static void check(bool cond, const char *desc)
{
	tests_run++;
	if (cond) {
		printf("PASS: %s\n", desc);
	} else {
		printf("FAIL: %s\n", desc);
		tests_failed++;
	}
}

static void flip_char_at(char *s, size_t idx)
{
	char cur = (char)tolower((unsigned char)s[idx]);
	size_t i;

	for (i = 0; i < strlen(TEST_CHARSET); ++i) {
		if (TEST_CHARSET[i] != cur) {
			s[idx] = TEST_CHARSET[i];
			return;
		}
	}
}

static void flip_b58_char_at(char *s, size_t idx)
{
	/* Flipping to a fixed different digit is enough to break the
	 * checksum for these purposes; avoid producing the same char. */
	s[idx] = (s[idx] == '9') ? '8' : '9';
}

static void to_upper_str(char *s)
{
	for (; *s; ++s)
		*s = (char)toupper((unsigned char)*s);
}

/* Known-good CashAddr/legacy pairs, already proven correct by the Phase 1
 * suite (test/cashaddr.c) -- all mainnet P2PKH. */
typedef struct {
	const char *cashaddr; /* prefixed, "bitcoincash:..." */
	const char *legacy;   /* paired legacy address */
} pair_t;

static const pair_t PAIRS[] = {
	{ "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a", "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu" },
	{ "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy", "1KXrWXciRDZUpQwQmuM1DbwsKDLYAYsVLR" },
	{ "bitcoincash:qqq3728yw0y47sqn6l2na30mcw6zm78dzqre909m2r", "16w1D5WRVKJuZUsSRzdLp9w3YGcgoxDXb" },
};
#define N_PAIRS (sizeof(PAIRS) / sizeof(PAIRS[0]))

int main(void)
{
	size_t i;
	uint8_t expect_hash160[20], got_hash160[20], version;
	uint8_t expect_script[25], got_script[25];
	int expect_len, got_len;
	char desc[320];
	char buf[128];
	bch_addr_type_t type;

	bch_set_cashaddr_prefix("bitcoincash");

	/* ---- cashaddr/legacy P2PKH pairs: shapes, agreement, typos ---- */
	for (i = 0; i < N_PAIRS; ++i) {
		const pair_t *v = &PAIRS[i];

		if (!local_legacy_decode(v->legacy, expect_hash160, &version) || version != 0x00) {
			snprintf(desc, sizeof(desc), "internal error: could not derive ground truth from %s", v->legacy);
			check(false, desc);
			continue;
		}
		expect_len = hash160_to_p2pkh_script(expect_script, expect_hash160);

		/* prefixed cashaddr */
		memset(got_hash160, 0, sizeof(got_hash160));
		type = bch_classify_address(v->cashaddr, "bitcoincash", got_hash160);
		snprintf(desc, sizeof(desc), "prefixed cashaddr classifies P2PKH and matches: %s", v->cashaddr);
		check(type == BCH_ADDR_CASHADDR_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);

		memset(got_script, 0, sizeof(got_script));
		got_len = bch_address_to_script((char *)got_script, v->cashaddr, "bitcoincash");
		snprintf(desc, sizeof(desc), "prefixed cashaddr script matches hash160-derived script: %s", v->cashaddr);
		check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len), desc);

		/* address_to_txn() (legacy signature) agrees too */
		memset(buf, 0, sizeof(buf));
		got_len = address_to_txn(buf, v->cashaddr, false, false);
		snprintf(desc, sizeof(desc), "address_to_txn() agrees with classifier for: %s", v->cashaddr);
		check(got_len == expect_len && !memcmp(buf, expect_script, (size_t)expect_len), desc);

		/* bare (prefixless) cashaddr */
		{
			const char *sep = strchr(v->cashaddr, ':');

			memset(got_hash160, 0, sizeof(got_hash160));
			type = bch_classify_address(sep + 1, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "bare cashaddr classifies P2PKH and matches: %s", sep + 1);
			check(type == BCH_ADDR_CASHADDR_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);
		}

		/* uppercase prefixed cashaddr */
		{
			strncpy(buf, v->cashaddr, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			to_upper_str(buf);
			memset(got_hash160, 0, sizeof(got_hash160));
			type = bch_classify_address(buf, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "uppercase prefixed cashaddr classifies P2PKH and matches: %s", buf);
			check(type == BCH_ADDR_CASHADDR_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);
		}

		/* typo in cashaddr payload (prefixed) */
		{
			strncpy(buf, v->cashaddr, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			flip_char_at(buf, strlen(buf) - 5); /* somewhere in the payload */
			type = bch_classify_address(buf, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "typo'd prefixed cashaddr rejected: %s", buf);
			check(type == BCH_ADDR_INVALID, desc);
			check(bch_address_to_script((char *)got_script, buf, "bitcoincash") == 0, "typo'd cashaddr yields zero-length script");
		}

		/* typo in bare cashaddr */
		{
			const char *sep = strchr(v->cashaddr, ':');

			strncpy(buf, sep + 1, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			flip_char_at(buf, 2);
			type = bch_classify_address(buf, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "typo'd bare cashaddr rejected: %s", buf);
			check(type == BCH_ADDR_INVALID, desc);
		}

		/* legacy address itself */
		memset(got_hash160, 0, sizeof(got_hash160));
		type = bch_classify_address(v->legacy, "bitcoincash", got_hash160);
		snprintf(desc, sizeof(desc), "legacy address classifies P2PKH and matches: %s", v->legacy);
		check(type == BCH_ADDR_LEGACY_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);

		memset(got_script, 0, sizeof(got_script));
		got_len = bch_address_to_script((char *)got_script, v->legacy, "bitcoincash");
		snprintf(desc, sizeof(desc), "legacy address script matches hash160-derived script: %s", v->legacy);
		check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len), desc);

		memset(buf, 0, sizeof(buf));
		got_len = address_to_txn(buf, v->legacy, false, false);
		snprintf(desc, sizeof(desc), "address_to_txn() agrees with classifier for legacy: %s", v->legacy);
		check(got_len == expect_len && !memcmp(buf, expect_script, (size_t)expect_len), desc);

		/* typo'd legacy address */
		{
			strncpy(buf, v->legacy, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			flip_b58_char_at(buf, strlen(buf) - 2);
			type = bch_classify_address(buf, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "typo'd legacy address rejected: %s", buf);
			check(type == BCH_ADDR_INVALID, desc);
			check(address_to_txn(buf, buf, false, false) == 0, "typo'd legacy address yields zero-length script via address_to_txn");
		}
	}

	/* ---- mainnet legacy P2SH: 3CWFddi6m4ndiGyKqzYvsFYagqDLPVMTzC,
	 * independently verified above to decode to the same hash160 as
	 * PAIRS[0] under version 0x05 ---- */
	{
		const char *p2sh_addr = "3CWFddi6m4ndiGyKqzYvsFYagqDLPVMTzC";

		if (!local_legacy_decode(p2sh_addr, expect_hash160, &version) || version != 0x05) {
			check(false, "internal error: could not derive ground truth for mainnet P2SH vector");
		} else {
			expect_len = hash160_to_p2sh_script(expect_script, expect_hash160);

			type = bch_classify_address(p2sh_addr, "bitcoincash", got_hash160);
			check(type == BCH_ADDR_LEGACY_P2SH && !memcmp(got_hash160, expect_hash160, 20),
			      "mainnet legacy P2SH classifies correctly and matches hash160");

			got_len = bch_address_to_script((char *)got_script, p2sh_addr, "bitcoincash");
			check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len),
			      "mainnet legacy P2SH script matches hash160-derived script");

			strncpy(buf, p2sh_addr, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			flip_b58_char_at(buf, strlen(buf) - 2);
			type = bch_classify_address(buf, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "typo'd legacy P2SH address rejected: %s", buf);
			check(type == BCH_ADDR_INVALID, desc);
		}
	}

	/* ---- mainnet P2SH cashaddr, synthesized independently (version
	 * byte 0x08: type=1/P2SH, size=0) against PAIRS[0]'s hash160 ---- */
	{
		char p2sh_cashaddr[96];

		if (!local_legacy_decode(PAIRS[0].legacy, expect_hash160, &version)) {
			check(false, "internal error: could not re-derive hash160 for P2SH cashaddr synth");
		} else if (!synth_cashaddr(p2sh_cashaddr, sizeof(p2sh_cashaddr), "bitcoincash", 0x08, expect_hash160)) {
			check(false, "internal error: failed to synthesize P2SH cashaddr");
		} else {
			expect_len = hash160_to_p2sh_script(expect_script, expect_hash160);

			type = bch_classify_address(p2sh_cashaddr, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "synthesized mainnet P2SH cashaddr classifies correctly: %s", p2sh_cashaddr);
			check(type == BCH_ADDR_CASHADDR_P2SH && !memcmp(got_hash160, expect_hash160, 20), desc);

			got_len = bch_address_to_script((char *)got_script, p2sh_cashaddr, "bitcoincash");
			check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len),
			      "synthesized mainnet P2SH cashaddr script matches hash160-derived script");

			flip_char_at(p2sh_cashaddr, strlen(p2sh_cashaddr) - 3);
			type = bch_classify_address(p2sh_cashaddr, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "typo'd P2SH cashaddr rejected: %s", p2sh_cashaddr);
			check(type == BCH_ADDR_INVALID, desc);
		}
	}

	/* ---- testnet/regtest legacy versions (0x6f/0xc4), synthesized via
	 * independent base58 encode is unnecessary here: these two strings
	 * were generated offline from PAIRS[0]'s hash160 with version bytes
	 * 0x6f/0xc4 and are re-verified via local_legacy_decode() below
	 * before use, exactly like the mainnet vectors. ---- */
	{
		const char *tn_p2pkh = "mrLC19Je2BuWQDkWSTriGYPyQJXKkkBmCx";
		const char *tn_p2sh = "2N44ThNe8NXHyv4bsX8AoVCXquBRW94Ls7W";

		if (!local_legacy_decode(tn_p2pkh, expect_hash160, &version) || version != 0x6f) {
			check(false, "internal error: could not derive ground truth for testnet P2PKH vector");
		} else {
			expect_len = hash160_to_p2pkh_script(expect_script, expect_hash160);

			/* Wrong network: classified against mainnet must fail
			 * (version byte 0x6f is not a mainnet P2PKH/P2SH byte) */
			type = bch_classify_address(tn_p2pkh, "bitcoincash", got_hash160);
			check(type == BCH_ADDR_INVALID, "testnet legacy P2PKH rejected under bitcoincash prefix");

			/* Right network: bchtest */
			type = bch_classify_address(tn_p2pkh, "bchtest", got_hash160);
			check(type == BCH_ADDR_LEGACY_P2PKH && !memcmp(got_hash160, expect_hash160, 20),
			      "testnet legacy P2PKH classifies correctly under bchtest prefix");
			got_len = bch_address_to_script((char *)got_script, tn_p2pkh, "bchtest");
			check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len),
			      "testnet legacy P2PKH script matches hash160-derived script");

			/* regtest shares the same non-mainnet version bytes */
			type = bch_classify_address(tn_p2pkh, "bchreg", got_hash160);
			check(type == BCH_ADDR_LEGACY_P2PKH && !memcmp(got_hash160, expect_hash160, 20),
			      "testnet legacy P2PKH also classifies correctly under bchreg prefix");
		}

		if (!local_legacy_decode(tn_p2sh, expect_hash160, &version) || version != 0xc4) {
			check(false, "internal error: could not derive ground truth for testnet P2SH vector");
		} else {
			expect_len = hash160_to_p2sh_script(expect_script, expect_hash160);

			type = bch_classify_address(tn_p2sh, "bitcoincash", got_hash160);
			check(type == BCH_ADDR_INVALID, "testnet legacy P2SH rejected under bitcoincash prefix");

			type = bch_classify_address(tn_p2sh, "bchtest", got_hash160);
			check(type == BCH_ADDR_LEGACY_P2SH && !memcmp(got_hash160, expect_hash160, 20),
			      "testnet legacy P2SH classifies correctly under bchtest prefix");
			got_len = bch_address_to_script((char *)got_script, tn_p2sh, "bchtest");
			check(got_len == expect_len && !memcmp(got_script, expect_script, (size_t)expect_len),
			      "testnet legacy P2SH script matches hash160-derived script");
		}
	}

	/* ---- bchtest: cashaddr checked against the wrong (bitcoincash)
	 * prefix must be rejected via checksum, and accepted under its own
	 * prefix ---- */
	{
		char bchtest_addr[96], bchreg_addr[96];

		if (!local_legacy_decode(PAIRS[1].legacy, expect_hash160, &version)) {
			check(false, "internal error: could not derive hash160 for bchtest cashaddr synth");
		} else if (!synth_cashaddr(bchtest_addr, sizeof(bchtest_addr), "bchtest", 0x00, expect_hash160) ||
			   !synth_cashaddr(bchreg_addr, sizeof(bchreg_addr), "bchreg", 0x00, expect_hash160)) {
			check(false, "internal error: failed to synthesize bchtest/bchreg cashaddr");
		} else {
			type = bch_classify_address(bchtest_addr, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "bchtest cashaddr rejected against bitcoincash prefix: %s", bchtest_addr);
			check(type == BCH_ADDR_INVALID, desc);

			type = bch_classify_address(bchtest_addr, "bchtest", got_hash160);
			snprintf(desc, sizeof(desc), "bchtest cashaddr accepted against bchtest prefix: %s", bchtest_addr);
			check(type == BCH_ADDR_CASHADDR_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);

			type = bch_classify_address(bchreg_addr, "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "bchreg cashaddr rejected against bitcoincash prefix: %s", bchreg_addr);
			check(type == BCH_ADDR_INVALID, desc);

			type = bch_classify_address(bchreg_addr, "bchreg", got_hash160);
			snprintf(desc, sizeof(desc), "bchreg cashaddr accepted against bchreg prefix: %s", bchreg_addr);
			check(type == BCH_ADDR_CASHADDR_P2PKH && !memcmp(got_hash160, expect_hash160, 20), desc);
		}
	}

	/* ---- bch_set_cashaddr_prefix()/address_to_txn() (legacy signature,
	 * used by stratifier.c) wiring: switching the active prefix changes
	 * what address_to_txn() accepts, exactly matching the classifier ---- */
	{
		const char *tn_p2pkh = "mrLC19Je2BuWQDkWSTriGYPyQJXKkkBmCx";

		bch_set_cashaddr_prefix("bitcoincash");
		check(!strcmp(bch_get_cashaddr_prefix(), "bitcoincash"), "bch_get_cashaddr_prefix() reflects bitcoincash");
		got_len = address_to_txn(buf, tn_p2pkh, false, false);
		check(got_len == 0, "address_to_txn() rejects testnet legacy address under bitcoincash prefix");

		bch_set_cashaddr_prefix("bchtest");
		check(!strcmp(bch_get_cashaddr_prefix(), "bchtest"), "bch_get_cashaddr_prefix() reflects bchtest");
		got_len = address_to_txn(buf, tn_p2pkh, false, false);
		check(got_len == 25, "address_to_txn() accepts testnet legacy address under bchtest prefix");

		bch_set_cashaddr_prefix("bitcoincash"); /* restore for remaining tests */
	}

	/* ---- garbage / edge cases ---- */
	check(bch_classify_address(NULL, "bitcoincash", got_hash160) == BCH_ADDR_INVALID, "NULL address rejected without crashing");
	check(bch_classify_address("", "bitcoincash", got_hash160) == BCH_ADDR_INVALID, "empty string rejected");
	check(bch_classify_address("rig01", "bitcoincash", got_hash160) == BCH_ADDR_INVALID, "'rig01' rejected");
	check(bch_classify_address("dogecoin:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze", "bitcoincash", got_hash160) == BCH_ADDR_INVALID,
	      "unknown-network-prefixed string rejected");
	check(bch_classify_address(
		"111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
		"bitcoincash", got_hash160) == BCH_ADDR_INVALID,
	      "overlong (>100 char) garbage string rejected (base58 length cap)");
	check(bch_classify_address("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "bitcoincash", got_hash160) == BCH_ADDR_INVALID,
	      "42-char garbage with a char outside the cashaddr charset ('b') rejected");
	check(bch_address_to_script((char *)got_script, "garbage", "bitcoincash") == 0, "bch_address_to_script() returns 0 for garbage input");
	check(address_to_txn(buf, "garbage", false, false) == 0, "address_to_txn() returns 0 for garbage input");

	/* ---- real production mainnet addresses sanity check ---- */
	{
		static const char *PRODUCTION_ADDRS[] = {
			"bitcoincash:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze",
			"bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",
		};
		size_t n;

		for (n = 0; n < sizeof(PRODUCTION_ADDRS) / sizeof(PRODUCTION_ADDRS[0]); ++n) {
			type = bch_classify_address(PRODUCTION_ADDRS[n], "bitcoincash", got_hash160);
			snprintf(desc, sizeof(desc), "production address classifies as P2PKH: %s", PRODUCTION_ADDRS[n]);
			check(type == BCH_ADDR_CASHADDR_P2PKH, desc);
		}
	}

	printf("\n%d/%d tests passed\n", tests_run - tests_failed, tests_run);
	return tests_failed ? 1 : 0;
}
