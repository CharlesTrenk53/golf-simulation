# Golfer Lifecycle Development Roadmap

This document records the intended long-horizon golfer-development architecture so future work can extend the current POC without collapsing distinct systems into one generic skill number.

## Core principle

More meaningful golf experience should generally create opportunity for improvement, but golfers should improve at different rates, in different skills, and at different stages of life. Temporary form, durable technique, technical readiness, underlying skill, physical capacity, confidence, and decision-making experience are separate systems.

## Current foundation

The simulator now separates:

- shot-specific technical ability: Drive, Approach, Short Game, Putt;
- career shot experience by shot type;
- factual golf activity: rounds, on-course exposure, practice repetitions, focus, quality, and timing;
- developmental opportunity/evidence versus raw repetitions;
- short-term technique bias;
- true-skill development and recovery;
- technical readiness/rust from inactivity and fast reacquisition of established skill;
- comfort and confidence;
- physical capacity: power, mobility, coordination, endurance;
- chronological age;
- shot assessment, willingness, personality, and decision behavior;
- shot-specific learning aptitude;
- shot-specific latent development potential.

POC-08 added shot-specific learning aptitude and age-sensitive acquisition/retention behavior. Aptitude controls how readily a golfer acquires genuinely new above-baseline skill. It does not directly accelerate deterioration or restoration of previously established skill.

POC-09 added shot-specific latent development potential. Potential is a persistent golfer trait that introduces soft resistance as developed skill approaches and exceeds the golfer's latent level. It is not a hard cap, does not alter deterioration or recovery, and remains neutral for legacy golfers unless a potential is explicitly assigned.

POC-10 added factual golf activity, playing/practice separation, practice quality and focus, elapsed-time effects, technical rust, and fast reacquisition. Practice creates developmental opportunity rather than direct skill points. Durable learning still flows through the existing aptitude, potential, age-plasticity, experience, and technique systems.

## Development systems

### 1. Skill-specific learning aptitude — IMPLEMENTED

Each golfer can learn different parts of golf at different rates. Aptitude remains separate from current skill, experience, recent form, potential, and practice quality.

### 2. Latent/personal potential — IMPLEMENTED

Long-run improvement shows diminishing returns based on individual, skill-specific latent potential rather than a universal hard cap.

Potential is implemented as soft acquisition resistance. A golfer can continue improving beyond potential, but each additional point becomes increasingly costly. Potential affects genuinely new above-baseline acquisition only; it does not protect against deterioration or slow recovery toward established skill.

Legacy compatibility is preserved by treating unconfigured potential as a neutral 100.0 value with a 1.0 acquisition modifier.

### 3. Practice and playing volume — IMPLEMENTED (POC-10)

Golf activity is represented factually before it reaches the learning model:

- rounds played and on-course shot exposure;
- practice repetitions by shot-family focus;
- practice quality/intent;
- dated play and practice activity;
- elapsed time and inactivity between activity events.

Raw repetitions and useful developmental evidence are deliberately separate. All meaningful repetitions can contribute to experience/entrenchment, while practice quality controls how much of that activity becomes useful technical evidence. Activity never awards skill directly.

Ten thousand shots accumulated rapidly versus over decades can therefore produce different development even when raw repetitions and evidence totals match, because the existing age-plasticity, retention, experience, and lifecycle systems operate over elapsed time.

POC-10 also separates durable technical ability from technical readiness. Inactivity produces an accelerating but saturating rust penalty: a week away causes little regression, months cause meaningful loss of usable skill, and long layoffs cause substantial temporary regression without erasing the golfer's underlying learned ability. Returning activity removes rust much faster than brand-new durable skill can be acquired.

The factual `GolfActivity` object is the source of activity accounting and timing. Long-term save-game serialization of this activity state should be handled by the eventual golfer persistence/save system rather than duplicating the same data inside multiple simulation layers.

### 4. Aging — IMPLEMENTED FOUNDATION

Age does not directly subtract from a generic golf skill rating. Aging modifies separate systems, including physical capacity, acquisition plasticity, and long-term retention.

Age-sensitive areas include:

- physical power;
- mobility;
- endurance;
- rate of acquiring new motor patterns;
- gradual erosion of acquired positive technical skill later in life.

Technical knowledge and course-management ability can continue to improve while physical distance capacity declines.

### 5. Distance versus technique — IMPLEMENTED FOUNDATION

Distance performance remains conceptually separable into learned technique and physical capacity. An older golfer can become technically better while losing clubhead-speed potential.

Driver and iron distance peak and eventually decline through changes in physical capacity, not because technical knowledge automatically disappears.

### 6. Coaching and lessons — FUTURE

The current development model exposes a coaching-candidate threshold. Future coaching should be able to:

- identify sustained deterioration;
- accelerate correction of technique bias;
- improve recovery efficiency;
- potentially alter learning conditions temporarily;
- reduce the chance of persistent bad habits becoming true-skill decline.

Coaching should not instantly restore skill.

### 7. Form, confidence, comfort, readiness, and true skill

These operate at different time scales:

- confidence/comfort: fastest;
- recent form: fast;
- technical readiness/rust: fast-to-medium and activity-sensitive;
- technique state: medium;
- true skill: slow;
- physical aging: very slow and age-dependent.

A golfer can therefore play poorly while still possessing high underlying skill, temporarily play above normal without immediately becoming permanently better, or return from a long layoff with substantial rust that quickly disappears once meaningful activity resumes.

### 8. Emergent golfer style

Playing style should increasingly emerge from the golfer's developed abilities rather than being entirely assigned by profile. A golfer who develops exceptional wedge and putting skill but weak Driver performance should naturally favor different decisions from a golfer whose power and Driver skill develop quickly.

The decision layer should consume the golfer that has developed, not override that history with a fixed archetype.

## POC-10 validation record

POC-10 was accepted after deterministic and stochastic validation covering:

- factual round/practice accounting;
- practice focus routing;
- practice-quality evidence weighting without direct skill awards;
- batching-invariant fractional evidence accounting;
- equal 10,000-repetition careers distributed over different timelines;
- accelerating inactivity rust from one week through multi-year layoffs;
- rapid reacquisition of established skill without changing durable skill;
- within-year activity cadence;
- seven full golf-life archetypes from age 16 through 76, including a late bloomer, grinder, weekend golfer, talented low-practice golfer, and former competitor.

The accepted former-competitor calibration preserves durable skill while allowing several points of usable-skill loss during low-activity years, with most rust recoverable after roughly 1,000 meaningful repetitions.

## Validation philosophy

Do not validate development only with very large repetition counts. Use realistic career-scale scenarios and keep 100,000 same-club shots only as an extreme mathematical stress ceiling.

Validation should include:

- stochastic seasons;
- short, medium, and multi-season slumps;
- hot streaks and recovery;
- different starting skills;
- different prior experience;
- different learning aptitudes;
- different latent potentials;
- different ages and physical trajectories;
- different practice and playing exposure;
- different activity cadences and inactivity periods.

A new development mechanism should be evaluated by its curve over golf time (shots, rounds, seasons, and elapsed calendar time), not only by whether unit tests pass.
