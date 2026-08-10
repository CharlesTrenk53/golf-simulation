# Golfer Lifecycle Development Roadmap

This document records the intended long-horizon golfer-development architecture so future work can extend the current POC without collapsing distinct systems into one generic skill number.

## Core principle

More meaningful golf experience should generally create opportunity for improvement, but golfers should improve at different rates, in different skills, and at different stages of life. Temporary form, durable technique, underlying skill, physical capacity, confidence, and decision-making experience are separate systems.

## Current foundation

The simulator already separates:

- shot-specific technical ability: Drive, Approach, Short Game, Putt;
- career shot experience by shot type;
- short-term technique bias;
- true-skill development and recovery;
- comfort and confidence;
- physical capacity: power, mobility, coordination, endurance;
- chronological age;
- shot assessment, willingness, personality, and decision behavior;
- shot-specific learning aptitude;
- shot-specific latent development potential.

POC-08 added shot-specific learning aptitude. Aptitude controls how readily a golfer acquires genuinely new above-baseline skill. It does not directly accelerate deterioration or restoration of previously established skill.

POC-09 adds shot-specific latent development potential. Potential is a persistent golfer trait that introduces soft resistance as developed skill approaches and exceeds the golfer's latent level. It is not a hard cap, does not alter deterioration or recovery, and remains neutral for legacy golfers unless a potential is explicitly assigned.

## Development systems

### 1. Skill-specific learning aptitude — IMPLEMENTED

Each golfer can learn different parts of golf at different rates. Aptitude remains separate from current skill, experience, recent form, and potential.

### 2. Latent/personal potential — IMPLEMENTED

Long-run improvement shows diminishing returns based on individual, skill-specific latent potential rather than a universal hard cap.

Potential is implemented as soft acquisition resistance. A golfer can continue improving beyond potential, but each additional point becomes increasingly costly. Potential affects genuinely new above-baseline acquisition only; it does not protect against deterioration or slow recovery toward established skill.

Legacy compatibility is preserved by treating unconfigured potential as a neutral 100.0 value with a 1.0 acquisition modifier.

### 3. Practice and playing volume — NEXT

Career experience should eventually distinguish:

- rounds played;
- practice repetitions;
- quality/intent of practice;
- inactivity;
- time elapsed between repetitions.

Ten thousand shots accumulated in five years should not necessarily have the same developmental meaning as ten thousand shots accumulated over thirty years.

The POC-09 stochastic career diagnostic already demonstrates that different exposure levels produce meaningfully different career shapes. The next step is to promote exposure from diagnostic configuration into a durable golfer-development system rather than leaving it as a test-harness input.

### 4. Aging

Age should not directly subtract from a generic golf skill rating. Aging should modify separate systems.

Likely age-sensitive areas include:

- physical power;
- mobility;
- endurance;
- recovery from fatigue/injury;
- rate of acquiring new motor patterns.

Technical knowledge and course-management ability may continue to improve while physical distance capacity declines.

### 5. Distance versus technique

Distance performance should remain conceptually separable into learned technique and physical capacity. An older golfer can become technically better while losing clubhead-speed potential.

Driver and iron distance are expected to peak and eventually decline through changes in physical capacity, not because technical knowledge automatically disappears.

### 6. Coaching and lessons

The current development model exposes a coaching-candidate threshold. Future coaching should be able to:

- identify sustained deterioration;
- accelerate correction of technique bias;
- improve recovery efficiency;
- potentially alter learning aptitude temporarily;
- reduce the chance of persistent bad habits becoming true-skill decline.

Coaching should not instantly restore skill.

### 7. Form, confidence, comfort, and true skill

These should continue to operate at different time scales:

- confidence/comfort: fastest;
- recent form: fast;
- technique state: medium;
- true skill: slow;
- physical aging: very slow and age-dependent.

A golfer can therefore play poorly while still possessing high underlying skill, or temporarily play above their normal level without immediately becoming permanently better.

### 8. Emergent golfer style

Playing style should increasingly emerge from the golfer's developed abilities rather than being entirely assigned by profile. A golfer who develops exceptional wedge and putting skill but weak Driver performance should naturally favor different decisions from a golfer whose power and Driver skill develop quickly.

The decision layer should consume the golfer that has developed, not override that history with a fixed archetype.

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
- different practice and playing exposure.

A new development mechanism should be evaluated by its curve over golf time (shots, rounds, seasons), not only by whether unit tests pass.
