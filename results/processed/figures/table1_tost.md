# Table 1: Two One-Sided Tests (TOST) Read-Path Parity

| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |
|:---|:---|:---|:---|:---|:---|
| 512B | 10057.6 | 299875.2 | +2881.57% | ±2.0% | **Outside Bound** |
| 1KB | 58894.7 | 318906.5 | +441.49% | ±2.0% | **Outside Bound** |
| 2KB | 96789.6 | 355762.0 | +267.56% | ±2.0% | **Outside Bound** |
| 4KB | 26303.8 | 383070.5 | +1356.33% | ±2.0% | **Outside Bound** |
| 8KB | 41398.9 | 470309.5 | +1036.04% | ±2.0% | **Outside Bound** |
| 16KB | 77314.3 | 667987.3 | +763.99% | ±2.0% | **Outside Bound** |
| 32KB | 149491.8 | 1024328.1 | +585.21% | ±2.0% | **Outside Bound** |
| 64KB | 291292.4 | 1778544.1 | +510.57% | ±2.0% | **Outside Bound** |
| 128KB | 598707.4 | 2699299.6 | +350.85% | ±2.0% | **Outside Bound** |
| 256KB | 1099988.3 | 5094571.5 | +363.15% | ±2.0% | **Outside Bound** |
| 512KB | 5287155.0 | 9521094.4 | +80.08% | ±2.0% | **Outside Bound** |
| 1MB | 4301684.4 | 90018085.1 | +1992.62% | ±2.0% | **Outside Bound** |

*Note on Methodology: The above table reflects single-run point estimates. Formal hypothesis rejection (H01/H02 with α=0.05) requires evaluating N >= 30 independent runs to compute Welch's degrees of freedom and two one-sided t-statistics against the ±2.0% equivalence margin. Under QEMU TCG software emulation, translated MSR helper overhead inflates small-block measurements.*
