# Focus Credits (FC) — Earning Rules

## Base Credits

Formula: `FC = floor(min × (min + 15) / 50)`

| Session | FC  |
|---------|-----|
| 10 min  | 5   |
| 15 min  | 9   |
| 20 min  | 14  |
| 25 min  | 20  |
| 30 min  | 27  |
| 45 min  | 54  |
| 60 min  | 90  |

Longer sessions earn disproportionately more per minute.

## Daily Streak Bonus

Based on cumulative focus minutes today (not session count):

| Minutes focused | Multiplier |
|-----------------|------------|
| 0–44 min        | 1.0x       |
| 45–74 min       | 1.1x       |
| 75–89 min       | 1.2x       |
| 90+ min         | 1.3x (cap) |

Counted on minutes focused *before* the session starts, so the session being
awarded doesn't raise its own tier.

Example: after 50 min of focus today, a 25-min session earns floor(20 × 1.1) = 22 FC.

## Tag Multiplier

Each tag has a configurable multiplier (default 1.0x), set in Settings > Tags.
A tag is required to start a session.

## Pause Penalty

Each session has a free pause allowance (default 10% of session length).
Pause time beyond that directly reduces effective credit time.

`effectiveSeconds = sessionSeconds - max(0, totalPausedSeconds - freePauseSeconds)`
`pauseMultiplier = effectiveSeconds / sessionSeconds`

Example: 25-min session, 10 min total paused, 10% free allowance (2.5 min):
Penalty = 10 - 2.5 = 7.5 min, effective = 17.5/25 = 0.7x → 20 × 0.7 = 14 FC

Configurable via Settings > Max Pause Before Penalty (%).

## Combined Calculation

All multipliers stack:

`Final FC = floor(base × streak × tag × pauseMultiplier)`

Editing a historical entry's tag recalculates the earned amount and adjusts the balance.
