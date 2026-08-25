AM_CPPFLAGS =  -I$(top_srcdir)/src
LDADD = $(top_srcdir)/src/libckpool.a

bin_PROGRAMS = sha256 cashaddr addrclassify

TESTS = sha256 cashaddr addrclassify

sha256_SOURCES = sha256.c
#sha256_LDADD = libckpool.a

cashaddr_SOURCES = cashaddr.c
#cashaddr_LDADD = libckpool.a

addrclassify_SOURCES = addrclassify.c
#addrclassify_LDADD = libckpool.a
