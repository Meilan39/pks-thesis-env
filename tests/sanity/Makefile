CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra

all: pks_sanity_test

pks_sanity_test: pks_sanity_test.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f pks_sanity_test

.PHONY: all clean
