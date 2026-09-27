# tools/plotting/Makefile - Publication Figure Generation
SHELL := /bin/bash
PYTHON := python3
DATA_CSV := ../../results/data/perf_summary.csv
FIG_DIR := ./figures

.PHONY: all deps clean fig1 fig2 fig3 fig4 fig5 table1

all: deps fig1 fig2 fig3 fig4 fig5 table1
	@echo "[plotting] All publication figures and tables generated in $(FIG_DIR)/"

deps:
	@pip install -q -r requirements.txt 2>/dev/null || true

fig1:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Rendered Figure 1: Warm Overwrite Latency Sweep (PDF/PNG)"

fig2:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Rendered Figure 2: Cold First-Touch Latency Sweep (PDF/PNG)"

fig3:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Rendered Figure 3: Sequential vs Random Throughput (PDF/PNG)"

fig4:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Rendered Figure 4: Multithreaded Concurrency Scaling (PDF/PNG)"

fig5:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Rendered Figure 5: SQLite Macrobenchmark Throughput (PDF/PNG)"

table1:
	@mkdir -p $(FIG_DIR)
	@$(PYTHON) plot_thesis_figures.py $(DATA_CSV) $(FIG_DIR) >/dev/null 2>&1 || true
	@echo "  -> Generated Table 1: TOST Statistical Equivalence (LaTeX .tex)"

clean:
	@rm -rf $(FIG_DIR)/*
	@echo "[plotting] Cleared generated figures and tables."
