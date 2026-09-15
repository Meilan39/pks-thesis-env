CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -D_GNU_SOURCE

all: fsx

fsx: fsx.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f fsx

.PHONY: all clean
