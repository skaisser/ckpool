/*
 * Standalone test for the CashAddr decoder (src/cashaddr_simple.c).
 *
 * Ground truth for the "paired legacy address" vectors is derived at
 * runtime from a tiny local base58check decoder + SHA256 implementation
 * rather than hardcoded hash160 constants, so the test does not depend on
 * transcribing hex correctly by hand.
 *
 * cashaddr_simple.c calls a couple of libckpool logging/hex-dump helpers
 * (logmsg, __bin2hex) that normally come from libckpool.a. When this test
 * is linked against the real archive (see test/Makefile.am) those strong
 * definitions win; the weak stubs below only apply when compiling this
 * file standalone against cashaddr_simple.c with no archive in play.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "cashaddr_simple.h"

/* ---- weak stubs for libckpool helpers cashaddr_simple.c depends on ---- */

#if defined(__GNUC__) || defined(__clang__)
#define WEAK_SYM __attribute__((weak))
#else
#define WEAK_SYM
#endif

WEAK_SYM void logmsg(int loglevel, const char *fmt, ...)
{
	(void)loglevel;
	(void)fmt;
}

WEAK_SYM void __bin2hex(void *vs, const void *vp, size_t len)
{
	static const char hexd[] = "0123456789abcdef";
	char *s = (char *)vs;
	const unsigned char *p = (const unsigned char *)vp;
	size_t i;

	for (i = 0; i < len; ++i) {
		s[i * 2] = hexd[p[i] >> 4];
		s[i * 2 + 1] = hexd[p[i] & 0xf];
	}
	s[len * 2] = '\0';
}

/* ------------------------------ SHA256 ---------------------------------
 * Public-domain style minimal SHA256, used only to verify base58check
 * checksums of the legacy address test vectors below.
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

static const uint32_t sha256_k[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static void sha256_transform(SHA256_CTX *ctx, const uint8_t data[])
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
		t1 = h + EP1(e) + CH(e, f, g) + sha256_k[i] + m[i];
		t2 = EP0(a) + MAJ(a, b, c);
		h = g; g = f; f = e; e = d + t1;
		d = c; c = b; b = a; a = t1 + t2;
	}

	ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
	ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void sha256_init(SHA256_CTX *ctx)
{
	ctx->datalen = 0;
	ctx->bitlen = 0;
	ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
	ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
	ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
	ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void sha256_update(SHA256_CTX *ctx, const uint8_t data[], size_t len)
{
	size_t i;

	for (i = 0; i < len; ++i) {
		ctx->data[ctx->datalen] = data[i];
		ctx->datalen++;
		if (ctx->datalen == 64) {
			sha256_transform(ctx, ctx->data);
			ctx->bitlen += 512;
			ctx->datalen = 0;
		}
	}
}

static void sha256_final(SHA256_CTX *ctx, uint8_t hash[32])
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
		sha256_transform(ctx, ctx->data);
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
	sha256_transform(ctx, ctx->data);

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

static void sha256_once(const uint8_t *data, size_t len, uint8_t out[32])
{
	SHA256_CTX ctx;

	sha256_init(&ctx);
	sha256_update(&ctx, data, len);
	sha256_final(&ctx, out);
}

/* --------------------------- base58check -------------------------------
 * Decodes a legacy P2PKH address into its 20-byte hash160, verifying the
 * base58check double-SHA256 checksum and the mainnet P2PKH version byte
 * (0x00). Used only to derive ground-truth hash160 values for the
 * CashAddr/legacy pairs in the valid test vectors.
 */

static bool base58_decode_25(const char *s, uint8_t out25[25])
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

static bool legacy_address_to_hash160(const char *addr, uint8_t hash160[20])
{
	uint8_t decoded[25];
	uint8_t chk1[32], chk2[32];

	if (!base58_decode_25(addr, decoded))
		return false;

	if (decoded[0] != 0x00) /* mainnet P2PKH version byte */
		return false;

	sha256_once(decoded, 21, chk1);
	sha256_once(chk1, 32, chk2);
	if (memcmp(chk2, decoded + 21, 4) != 0)
		return false;

	memcpy(hash160, decoded + 1, 20);
	return true;
}

/* --------------------- mini independent CashAddr encoder -----------------
 * Used only to synthesize a genuinely valid, correctly-checksummed CashAddr
 * for a *different* network prefix (e.g. "bchtest"), so the negative test
 * suite can prove that decode_checked rejects it against "bitcoincash" via
 * checksum (prefixless case) and not merely via string-prefix mismatch.
 * Deliberately not shared code with cashaddr_simple.c.
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

/* Flip the character at index idx (within the whole string s) to a
 * different CashAddr charset character, corrupting checksum or payload. */
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

static void to_upper_str(char *s)
{
	for (; *s; ++s)
		*s = (char)toupper((unsigned char)*s);
}

typedef struct {
	const char *cashaddr; /* prefixed, "bitcoincash:..." */
	const char *legacy;   /* paired legacy address for hash160 ground truth */
} valid_vector_t;

static const valid_vector_t VALID_VECTORS[] = {
	{ "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a", "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu" },
	{ "bitcoincash:qr95sy3j9xwd2ap32xkykttr4cvcu7as4y0qverfuy", "1KXrWXciRDZUpQwQmuM1DbwsKDLYAYsVLR" },
	{ "bitcoincash:qqq3728yw0y47sqn6l2na30mcw6zm78dzqre909m2r", "16w1D5WRVKJuZUsSRzdLp9w3YGcgoxDXb" },
};
#define N_VALID (sizeof(VALID_VECTORS) / sizeof(VALID_VECTORS[0]))

static const char *PRODUCTION_ADDRS[] = {
	"bitcoincash:qqqupxkkrjew738czfzpz5e33sej6wm9zqdquq0aze",
	"bitcoincash:qregedwmg8tr2ymnp8j6f0tesuj4r9lqnqjfmlvj6w",
};
#define N_PROD (sizeof(PRODUCTION_ADDRS) / sizeof(PRODUCTION_ADDRS[0]))

int main(void)
{
	size_t i;
	uint8_t expect_hash160[20];
	uint8_t got_hash160[20];
	bool is_p2sh;
	char desc[256];
	char buf[128];
	char buf2[128];

	/* ---- valid vectors: prefixed, lowercase ---- */
	for (i = 0; i < N_VALID; ++i) {
		const valid_vector_t *v = &VALID_VECTORS[i];

		if (!legacy_address_to_hash160(v->legacy, expect_hash160)) {
			snprintf(desc, sizeof(desc), "internal error: could not derive hash160 from legacy %s", v->legacy);
			check(false, desc);
			continue;
		}

		is_p2sh = true;
		memset(got_hash160, 0, sizeof(got_hash160));
		snprintf(desc, sizeof(desc), "valid prefixed: %s decodes and matches legacy twin", v->cashaddr);
		check(cashaddr_decode_checked(v->cashaddr, "bitcoincash", got_hash160, &is_p2sh) &&
		      !is_p2sh &&
		      memcmp(got_hash160, expect_hash160, 20) == 0,
		      desc);

		/* prefixless */
		{
			const char *sep = strchr(v->cashaddr, ':');
			is_p2sh = true;
			memset(got_hash160, 0, sizeof(got_hash160));
			snprintf(desc, sizeof(desc), "valid prefixless: %s decodes and matches legacy twin", sep + 1);
			check(cashaddr_decode_checked(sep + 1, "bitcoincash", got_hash160, &is_p2sh) &&
			      !is_p2sh &&
			      memcmp(got_hash160, expect_hash160, 20) == 0,
			      desc);
		}

		/* uppercase, prefixed */
		{
			strncpy(buf, v->cashaddr, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			to_upper_str(buf);
			is_p2sh = true;
			memset(got_hash160, 0, sizeof(got_hash160));
			snprintf(desc, sizeof(desc), "valid uppercase prefixed: %s decodes and matches legacy twin", buf);
			check(cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh) &&
			      !is_p2sh &&
			      memcmp(got_hash160, expect_hash160, 20) == 0,
			      desc);
		}

		/* uppercase, prefixless */
		{
			const char *sep = strchr(v->cashaddr, ':');
			strncpy(buf, sep + 1, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			to_upper_str(buf);
			is_p2sh = true;
			memset(got_hash160, 0, sizeof(got_hash160));
			snprintf(desc, sizeof(desc), "valid uppercase prefixless: %s decodes and matches legacy twin", buf);
			check(cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh) &&
			      !is_p2sh &&
			      memcmp(got_hash160, expect_hash160, 20) == 0,
			      desc);
		}
	}

	/* ---- production pool addresses: must decode, P2PKH ---- */
	for (i = 0; i < N_PROD; ++i) {
		is_p2sh = true;
		memset(got_hash160, 0, sizeof(got_hash160));
		snprintf(desc, sizeof(desc), "production address decodes as P2PKH: %s", PRODUCTION_ADDRS[i]);
		check(cashaddr_decode_checked(PRODUCTION_ADDRS[i], "bitcoincash", got_hash160, &is_p2sh) && !is_p2sh, desc);
	}

	/* ---- invalid: one-character payload typo (checksum failure) ---- */
	for (i = 0; i < N_VALID; ++i) {
		const char *sep = strchr(VALID_VECTORS[i].cashaddr, ':');
		size_t sep_off = (size_t)(sep - VALID_VECTORS[i].cashaddr);

		strncpy(buf, VALID_VECTORS[i].cashaddr, sizeof(buf) - 1);
		buf[sizeof(buf) - 1] = '\0';
		flip_char_at(buf, sep_off + 1); /* first payload char */
		is_p2sh = false;
		snprintf(desc, sizeof(desc), "typo in payload rejected: %s", buf);
		check(!cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh), desc);

		/* last character changed (last checksum symbol) */
		strncpy(buf2, VALID_VECTORS[i].cashaddr, sizeof(buf2) - 1);
		buf2[sizeof(buf2) - 1] = '\0';
		flip_char_at(buf2, strlen(buf2) - 1);
		snprintf(desc, sizeof(desc), "typo in last character rejected: %s", buf2);
		check(!cashaddr_decode_checked(buf2, "bitcoincash", got_hash160, &is_p2sh), desc);
	}

	/* ---- invalid: mixed case ---- */
	{
		const char *a = "Bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a";
		const char *b = "bitcoincash:Qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a";

		check(!cashaddr_decode_checked(a, "bitcoincash", got_hash160, &is_p2sh), "mixed case prefix rejected");
		check(!cashaddr_decode_checked(b, "bitcoincash", got_hash160, &is_p2sh), "mixed case payload rejected");
	}

	/* ---- invalid: wrong prefix (string mismatch, prefixed input) ---- */
	{
		const char *sep = strchr(VALID_VECTORS[0].cashaddr, ':');

		snprintf(buf, sizeof(buf), "bchtest:%s", sep + 1);
		check(!cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh), "bchtest: prefix on mainnet payload rejected");

		snprintf(buf, sizeof(buf), "dogecoin:%s", sep + 1);
		check(!cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh), "dogecoin: prefix rejected");
	}

	/* ---- invalid: genuinely valid bchtest checksum tested against
	 * expected_prefix "bitcoincash" (prefixed and prefixless) ---- */
	{
		uint8_t hash160_zero[20];
		char synth[128];
		char synth_prefixless[128];
		const char *psep;

		memset(hash160_zero, 0x11, sizeof(hash160_zero));
		check(synth_cashaddr(synth, sizeof(synth), "bchtest", 0x00, hash160_zero),
		      "internal: synthesized valid bchtest address");

		check(!cashaddr_decode_checked(synth, "bitcoincash", got_hash160, &is_p2sh),
		      "valid bchtest address rejected against expected_prefix bitcoincash (prefixed)");

		psep = strchr(synth, ':');
		strncpy(synth_prefixless, psep + 1, sizeof(synth_prefixless) - 1);
		synth_prefixless[sizeof(synth_prefixless) - 1] = '\0';
		check(!cashaddr_decode_checked(synth_prefixless, "bitcoincash", got_hash160, &is_p2sh),
		      "valid bchtest payload (prefixless) rejected against expected_prefix bitcoincash via checksum");

		/* sanity: the synthesized address is genuinely valid for its own network */
		check(cashaddr_decode_checked(synth, "bchtest", got_hash160, &is_p2sh) && !is_p2sh &&
		      memcmp(got_hash160, hash160_zero, 20) == 0,
		      "internal: synthesized bchtest address decodes correctly against its own prefix");
	}

	/* ---- invalid: truncated payload ---- */
	{
		const char *sep = strchr(VALID_VECTORS[0].cashaddr, ':');
		size_t plen = strlen(sep + 1);

		strncpy(buf, sep + 1, plen - 4);
		buf[plen - 4] = '\0';
		snprintf(desc, sizeof(desc), "truncated payload rejected: %s", buf);
		check(!cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh), desc);
	}

	/* ---- invalid: empty string ---- */
	check(!cashaddr_decode_checked("", "bitcoincash", got_hash160, &is_p2sh), "empty string rejected");

	/* ---- invalid: charset violations ---- */
	{
		const char bad_chars[] = { 'b', 'i', 'o', '1' };
		size_t ci;

		for (ci = 0; ci < sizeof(bad_chars); ++ci) {
			const char *sep = strchr(VALID_VECTORS[0].cashaddr, ':');

			strncpy(buf, sep + 1, sizeof(buf) - 1);
			buf[sizeof(buf) - 1] = '\0';
			buf[0] = bad_chars[ci];
			snprintf(desc, sizeof(desc), "invalid charset char '%c' rejected: %s", bad_chars[ci], buf);
			check(!cashaddr_decode_checked(buf, "bitcoincash", got_hash160, &is_p2sh), desc);
		}
	}

	printf("\n%d/%d tests passed\n", tests_run - tests_failed, tests_run);
	return tests_failed == 0 ? 0 : 1;
}
