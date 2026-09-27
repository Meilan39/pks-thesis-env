# tests/Makefile - Sub-directory aggregator for unit & compliance tests
SUBDIRS := pks-unit sanity fsx pjd

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
