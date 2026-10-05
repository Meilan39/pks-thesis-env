# Table 1: Two One-Sided Tests (TOST) Read-Path Parity

| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |
|:---|:---|:---|:---|:---|:---|
| 512B | 10257.9 | 11106.6 | +8.27% | ±2.0% | **Outside Bound** |
| 1KB | 14514.9 | 14867.2 | +2.43% | ±2.0% | **Outside Bound** |
| 2KB | 21260.8 | 23143.3 | +8.85% | ±2.0% | **Outside Bound** |
| 4KB | 33724.6 | 34660.3 | +2.77% | ±2.0% | **Outside Bound** |
| 8KB | 65050.5 | 61344.9 | -5.70% | ±2.0% | **Outside Bound** |
| 16KB | 147193.3 | 106295.9 | -27.78% | ±2.0% | **Outside Bound** |
| 32KB | 195779.2 | 219985.7 | +12.36% | ±2.0% | **Outside Bound** |
| 64KB | 731040.2 | 395120.3 | -45.95% | ±2.0% | **Outside Bound** |
| 128KB | 840713.6 | 836188.6 | -0.54% | ±2.0% | **Within Bound** |
| 256KB | 2799955.1 | 1498548.5 | -46.48% | ±2.0% | **Outside Bound** |
| 512KB | 3186264.2 | 3320867.0 | +4.22% | ±2.0% | **Outside Bound** |
| 1MB | 6314820.3 | 6445062.5 | +2.06% | ±2.0% | **Outside Bound** |

*Note: Point estimates evaluate read-path domain switching neutrality against the ±2.0% practical equivalence margin.*
