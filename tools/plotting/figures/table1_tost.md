# Table 1: Two One-Sided Tests (TOST) Read-Path Parity

| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |
|:---|:---|:---|:---|:---|:---|
| 512B | 10959.3 | 12089.3 | +10.31% | ±2.0% | **Outside Bound** |
| 1KB | 14293.1 | 15814.2 | +10.64% | ±2.0% | **Outside Bound** |
| 2KB | 19691.9 | 21466.4 | +9.01% | ±2.0% | **Outside Bound** |
| 4KB | 33815.7 | 34450.5 | +1.88% | ±2.0% | **Within Bound** |
| 8KB | 64741.0 | 61720.7 | -4.67% | ±2.0% | **Outside Bound** |
| 16KB | 125061.1 | 122293.0 | -2.21% | ±2.0% | **Outside Bound** |
| 32KB | 247317.7 | 221887.6 | -10.28% | ±2.0% | **Outside Bound** |
| 64KB | 429300.7 | 463227.5 | +7.90% | ±2.0% | **Outside Bound** |
| 128KB | 802621.1 | 741742.5 | -7.58% | ±2.0% | **Outside Bound** |
| 256KB | 1814717.9 | 1678069.7 | -7.53% | ±2.0% | **Outside Bound** |
| 512KB | 3202084.2 | 3491922.3 | +9.05% | ±2.0% | **Outside Bound** |
| 1MB | 6294432.5 | 6912248.1 | +9.82% | ±2.0% | **Outside Bound** |

*Note: Point estimates evaluate read-path domain switching neutrality against the ±2.0% practical equivalence margin.*
