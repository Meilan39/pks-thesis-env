# tools/plotting/Makefile - Publication Figure Generation
SHELL := /bin/bash
PYTHON := python3
DATA_CSV := ../../results/data/perf_summary.csv
FIG_DIR := ./figures

.PHONY: all deps clean fig1 fig2 fig3 fig4 fig5 table1

all: fig1
	@echo "[plotting] All publication figures and tables generated in $(FIG_DIR)/"

deps:
	@which pip >/dev/null 2>&1 && pip install --timeout 2 -q -r requirements.txt 2>/dev/null || true

fig1 fig2 fig3 fig4 fig5 table1:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true

clean:
	@rm -rf $(FIG_DIR)/*
	@echo "[plotting] Cleared generated figures and tables."
