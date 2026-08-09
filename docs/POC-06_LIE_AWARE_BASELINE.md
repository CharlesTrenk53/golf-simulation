# POC-06 Lie-Aware Monte Carlo Baseline

Validated after POC-06E (`Hazard-Aware Targeting & Water Relief`).

Simulation: 1,000 autonomous holes per golfer on the same lie-aware course context, using seeds 1–1000.

| Golfer | Mean | Median | Best | Worst | Finish rate | Water / hole |
|---|---:|---:|---:|---:|---:|---:|
| Wild Bill | 3.176 | 2 | 2 | 12 | 99.6% | 0.592 |
| Reckless Rick | 7.993 | 8 | 3 | 13 | 81.7% | 2.199 |
| Careful Carl | 6.005 | 6 | 4 | 13 | 99.5% | 0.129 |

## Behavioral interpretation

- Wild Bill attacks 100% of the time. His high driving ability makes the aggressive strategy highly productive, although he accepts meaningful water exposure.
- Reckless Rick attacks frequently despite much lower driving ability. His combination of low ability and high risk tolerance creates high water exposure and volatile scoring.
- Careful Carl lays up frequently and strongly suppresses water risk, trading scoring potential for consistency.

## Why this baseline is preserved

This is the first Monte Carlo checkpoint after course surfaces, lie-dependent decisions, authoritative water outcomes, hazard-aware safe targeting, and playable water relief were integrated. Future simulation changes should be compared with this checkpoint so behavioral regressions are visible rather than hidden by added complexity.
