# POC-09 Closeout — Latent Development Potential

## Goal

Add individual, skill-specific latent potential to long-horizon golfer development without turning potential into a hard cap or collapsing it into learning aptitude.

The intended distinction is:

- **Aptitude** controls how readily a golfer learns.
- **Potential** controls how much resistance appears as developed skill becomes highly advanced for that golfer.

## Implemented architecture

### Persistent golfer property

`scenes/golfer.gd` stores skill-specific latent potential independently from current skill, experience, aptitude, physical capacity, confidence, and form.

Missing potential values resolve to 100.0. This deliberately preserves legacy behavior for golfers that predate POC-09.

### Soft development resistance

`simulation/development_potential.gd` implements a continuous resistance curve.

- Far below potential, acquisition is minimally constrained.
- Resistance rises smoothly as current skill approaches potential.
- At potential, acquisition is substantially harder but still possible.
- Above potential, continued development remains possible and asymptotically approaches a small positive floor.
- A potential of 100.0 is explicitly neutral and always returns a 1.0 acquisition modifier.

### Technique/skill integration

`simulation/technique_skill_development.gd` applies potential only to genuinely new positive above-baseline skill acquisition.

Potential does **not**:

- accelerate or protect deterioration;
- change restoration from below baseline;
- alter transient form directly;
- replace age plasticity;
- replace aptitude;
- replace existing development resistance from already-acquired skill.

## Validation

### Unit and integration coverage

POC-09 tests verify:

- resistance increases smoothly near latent potential;
- potential remains soft rather than becoming a hard cap;
- potential can differ by shot family;
- higher potential produces greater long-run acquisition under identical evidence;
- deterioration is unchanged by potential;
- recovery is unchanged by potential;
- maximum/unconfigured potential preserves legacy-neutral acquisition;
- persistent golfer potential is read correctly by the development model.

### Controlled career diagnostics

Potential-only diagnostics confirmed gradual divergence between otherwise identical golfers.

Aptitude × potential diagnostics confirmed that:

- higher aptitude controls early acquisition rate;
- lower potential increasingly resists later development;
- crossover can occur when the aptitude advantage is moderate and the potential difference is large enough;
- a large aptitude advantage can remain ahead for a full career, which is intentionally possible.

### Stochastic lifetime diagnostic

The final realism-oriented diagnostic simulates multiple distinct golfer careers from age 16 through 76 with:

- different starting technical abilities;
- skill-specific aptitude;
- skill-specific potential;
- different physical capacities;
- different playing/practice exposure;
- stochastic form and execution;
- age-based learning plasticity;
- annual technical retention;
- physical lifecycle aging.

The final career spread produced believable differentiation among an Early Phenom, Late Bloomer, Grinder, Talented Underachiever, Steady Competitor, and Club Golfer.

The Late Bloomer exposure profile was revised after visual review so early development remains flatter and the strongest improvement occurs later, especially through roughly ages 30–50.

## POC-09 status

- Soft potential architecture: **GREEN**
- Aptitude/potential separation: **GREEN**
- Skill-specific behavior: **GREEN**
- No hard cap: **GREEN**
- Deterioration/recovery isolation: **GREEN**
- Legacy compatibility: **GREEN**
- Persistent golfer integration: **GREEN**
- Controlled career behavior: **GREEN**
- Stochastic lifetime realism: **GREEN**

## Next roadmap item

The next major lifecycle system is **practice and playing volume**.

POC-09 used exposure differences successfully inside diagnostics, but exposure is still supplied by the test harness. The next POC should promote rounds played, practice repetitions, practice quality/intent, inactivity, and elapsed time into persistent development inputs so a golfer's actual activity history determines how development opportunities accumulate.
