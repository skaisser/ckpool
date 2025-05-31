AM_CPPFLAGS =  -I$(top_srcdir)/src
LDADD = $(top_srcdir)/src/libckpool.a

sha256_native_objs :=
if HAVE_AVX2
sha256_native_objs += ../src/sha256_code_release/sha256_avx2_rorx2.A
endif
if HAVE_AVX1
sha256_native_objs += ../src/sha256_code_release/sha256_avx1.A
endif
if HAVE_SSE4
sha256_native_objs += ../src/sha256_code_release/sha256_sse4.A
endif
if HAVE_ARM_SHA2
sha256_native_objs += ../src/sha256_arm_shani.o
endif



bin_PROGRAMS = sha256

TESTS = sha256

sha256_SOURCES = sha256.c
#sha256_LDADD = libckpool.a
