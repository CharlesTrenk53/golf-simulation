# POC-12 — Autonomous Multi-Hole Round

## Goal

Prove that the playable-hole architecture from POC-11 scales into an ordered course and autonomous round without special-case logic for a particular number of holes.

## POC-12A — Course Definition

A `CourseDefinition` owns ordered `HoleDefinition` files and derives course totals from those holes.

Proving course:

1. Decision Point — par 4 — 425 yards
2. Carry Question — par 3 — 165 yards
3. Long Way Home — par 5 — 510 yards

Default-tee total: 1,100 yards, par 12.

### GREEN criterion

The course loads from one manifest, validates course membership and 1..N order, exposes holes by index/number, and derives total par/yardage from the loaded hole definitions.

## Next slices

- POC-12B: round state and scorekeeping.
- POC-12C: autonomous hole-to-hole progression.
- POC-12D: watchable three-hole mini-course.

The round architecture must remain indifferent to whether the course contains 3, 9, or 18 holes.
