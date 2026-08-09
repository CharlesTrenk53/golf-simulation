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
- shot assessment, willingness, personality, and decision behavior.

POC-08 now also supports shot-specific learning aptitude. This aptitude affects acquisition of genuinely new above-baseline skill. It does not directly accelerate deterioration or restoration of previously established skill.

## Future development systems

### 1. Skill-specific learning aptitude

Each golfer should be able to learn different parts of golf at different rates. Examples include faster iron development with slower putting development, or strong touch-skill learning with slower Driver development.

Aptitude should remain separate from current skill, experience, and recent form.

### 2. Latent/personal potential

Long-run improvement should show diminishing returns and should eventually reflect individual potential rather than a universal hard cap. Potential may differ by skill and may interact with physical traits.

Potential should be implemented as soft resistance, not an arbitrary maximum that suddenly stops learning.

### 3. Practice and playing volume

Career experience should eventually distinguish:

- rounds played;
- practice repetitions;
- quality/intent of practice;
- inactivity;
- time elapsed between repetitions.

Ten thousand shots accumulated in five years should not necessarily have the same developmental meaning as ten thousand shots accumulated over thirty years.

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
- eventually different ages and physical trajectories.

A new development mechanism should be evaluated by its curve over golf time (shots, rounds, seasons), not only by whether unit tests pass.
