# Table 1: Two One-Sided Tests (TOST) Read-Path Parity

| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |
|:---|:---|:---|:---|:---|:---|
| 512B | 293554.4 | 305129.5 | +3.94% | ±2.0% | **Outside Bound** |
| 1KB | 331260.0 | 324369.5 | -2.08% | ±2.0% | **Outside Bound** |
| 2KB | 347983.8 | 369476.8 | +6.18% | ±2.0% | **Outside Bound** |
| 4KB | 646063.4 | 522885.2 | -19.07% | ±2.0% | **Outside Bound** |
| 8KB | 455406.6 | 507854.5 | +11.52% | ±2.0% | **Outside Bound** |
| 16KB | 1686281.8 | 854476.5 | -49.33% | ±2.0% | **Outside Bound** |
| 32KB | 1105041.1 | 1081291.6 | -2.15% | ±2.0% | **Outside Bound** |
| 64KB | 4564616.8 | 4388042.8 | -3.87% | ±2.0% | **Outside Bound** |
| 128KB | 3053685.1 | 5950570.6 | +94.87% | ±2.0% | **Outside Bound** |
| 256KB | 4931199.5 | 5336994.4 | +8.23% | ±2.0% | **Outside Bound** |
| 512KB | 9256805.3 | 10183039.1 | +10.01% | ±2.0% | **Outside Bound** |
| 1MB | 18084706.7 | 20193358.4 | +11.66% | ±2.0% | **Outside Bound** |

*Note on Methodology: The above table reflects single-run point estimates. Formal hypothesis rejection (H01/H02 with α=0.05) requires evaluating N >= 30 independent runs to compute Welch's degrees of freedom and two one-sided t-statistics against the ±2.0% equivalence margin. Under QEMU TCG software emulation, translated MSR helper overhead inflates small-block measurements.*
