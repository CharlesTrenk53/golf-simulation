# POC-06 Closeout — Course Context and Lie-Aware Golf

POC-06 is complete and serves as the validated checkpoint before club and shot-selection work begins.

## Validated capabilities

- Course context with tee, fairway, rough, bunker, green, and water surfaces.
- Lie quality modifies shot reward, risk, dispersion, and effective distance.
- Lie-dependent decision generation:
  - Fairway/tee can support aggressive attack choices.
  - Rough removes unrealistic driver-style attacks and generates recovery advances.
  - Bunkers generate bunker-specific escape choices.
  - Green forces putting context.
- Course geometry is authoritative for water outcomes.
- Safe targets avoid intentionally aiming into water.
- Water shots receive a one-stroke penalty.
- Red-penalty-area style lateral relief is modeled from the water-entry point, with the drop kept no nearer the hole.
- Visual demo explicitly shows water penalty scoring and relief.
- Autonomous visual comparison runs Wild Bill, Reckless Rick, and Careful Carl through the same lie-aware hole.
- Headless Monte Carlo simulation runs 1,000 holes per golfer and remains part of CI validation.

## Preserved Monte Carlo baseline

The first validated lie-aware baseline after hazard-aware targeting and water relief was:

| Golfer | Mean | Median | Best | Worst | Finish rate | Water / hole |
|---|---:|---:|---:|---:|---:|---:|
| Wild Bill | 3.176 | 2 | 2 | 12 | 99.6% | 0.592 |
| Reckless Rick | 7.993 | 8 | 3 | 13 | 81.7% | 2.199 |
| Careful Carl | 6.005 | 6 | 4 | 13 | 99.5% | 0.129 |

These values are preserved as a behavioral checkpoint rather than a final tuning target.

## Behavioral interpretation

- Wild Bill consistently favors aggression and benefits from his high driving ability.
- Reckless Rick combines high risk tolerance with low driving ability, creating volatility and frequent penalty exposure.
- Careful Carl strongly favors safer play and suppresses water risk at the expense of scoring potential.

## Checkpoint status

POC-06 is closed. Future development should branch from this completed state and should not modify the `poc-06-course-context` branch except for deliberate corrective maintenance.

Next milestone: POC-07 — Shot and Club Selection.
