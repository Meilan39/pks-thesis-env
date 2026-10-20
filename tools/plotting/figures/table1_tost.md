# Table 1: Two One-Sided Tests (TOST) Read-Path Parity

| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |
|:---|:---|:---|:---|:---|:---|
| 512B | 11003.9 | 9701.7 | -11.83% | ±2.0% | **Outside Bound** |
| 1KB | 13101.2 | 13026.9 | -0.57% | ±2.0% | **Within Bound** |
| 2KB | 18506.3 | 17110.8 | -7.54% | ±2.0% | **Outside Bound** |
| 4KB | 28154.7 | 26692.4 | -5.19% | ±2.0% | **Outside Bound** |
| 8KB | 39848.9 | 41142.3 | +3.25% | ±2.0% | **Outside Bound** |
| 16KB | 69240.9 | 81858.0 | +18.22% | ±2.0% | **Outside Bound** |
| 32KB | 143031.4 | 156411.7 | +9.35% | ±2.0% | **Outside Bound** |
| 64KB | 269497.8 | 304645.6 | +13.04% | ±2.0% | **Outside Bound** |
| 128KB | 503418.4 | 598700.1 | +18.93% | ±2.0% | **Outside Bound** |
| 256KB | 1176065.8 | 1102989.5 | -6.21% | ±2.0% | **Outside Bound** |
| 512KB | 2229743.0 | 2355057.8 | +5.62% | ±2.0% | **Outside Bound** |
| 1MB | 4602630.0 | 4856781.6 | +5.52% | ±2.0% | **Outside Bound** |

*Note: Point estimates evaluate read-path domain switching neutrality against the ±2.0% practical equivalence margin.*
