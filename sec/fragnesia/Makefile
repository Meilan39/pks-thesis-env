CC ?= gcc
CFLAGS ?= -O2 -Wall -pthread

all: exp

exp: exp.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f exp *.o *.log

.PHONY: all clean
