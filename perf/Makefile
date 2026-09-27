# perf/Makefile - Sub-directory aggregator for performance benchmarks
SUBDIRS := fio concurrency sqlite

.PHONY: all clean $(SUBDIRS)

all:
	@for dir in $(SUBDIRS); do \
		if [ -f "$$dir/Makefile" ]; then \
			$(MAKE) -C "$$dir" all || exit 1; \
		fi \
	done

clean:
	@for dir in $(SUBDIRS); do \
		if [ -f "$$dir/Makefile" ]; then \
			$(MAKE) -C "$$dir" clean || true; \
		fi \
	done
