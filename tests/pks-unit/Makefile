CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra

all: test_pks

test_pks: test_pks.c
	$(CC) $(CFLAGS) -o $@ $< -lpthread

clean:
	rm -f test_pks

.PHONY: all clean
