# Lineup projection card

Build 28 cache follow-up: a cached lineup or opponent scoreboard never supplies a current projected advantage. The comparison resumes only after both same-week snapshots refresh successfully. Last-known lineup content stays noneditable until its fresh baseline arrives; see [startup contract](performance-startup.md).

Implemented in private build **0.5.3 (27)**. [Current status](current-status.md) records verification and delivery; [roadmap](roadmap.md) retains live-week and distribution gates.

- Align the card with the roster cards. Keep the edited lineup's weekly projection prominent on the left; on the right, show the smaller signed margin with `pts` and the opponent's full name beneath it.
- Positive differences use green and `+`; negative differences use orange and `−`. Display one decimal, matching the lineup projection. Rounded zero reads **Even**, in a neutral color. VoiceOver names the full opponent and says points ahead, behind or even; direction never relies on color alone.
- Move Current lineup / Unsaved changes / Incomplete / Submitted below the divider, beside the kickoff-lock note. Both use plain icon-and-text metadata, not button-like capsules. Stack when width or Dynamic Type requires it. Retain the last-submitted time in accessibility information without a third visible footer item.
- A draft substitution recalculates immediately. It does not submit a lineup; existing review, validation and readback protections are unchanged.

## Data contract

Margin = **edited starter projection total − opponent starter projection total**. This compares weekly projections, not a live-score lead, remaining-points forecast or win probability. Actual game scores and the owner's saved scoreboard projection are not substituted into the calculation.

Use existing `AppModel.scores` and `lineup` snapshots. Add no API requests, cache changes, polling, persistent data or permissions. Require the same selected week, a confirmed workspace and exactly one matchup containing the exact owner franchise ID. Never use the featured-matchup fallback. Missing games, byes, self-matchups and ambiguous doubleheaders omit the comparison.

Both sides need complete, unique starter sets and finite projections. The edited lineup must satisfy its position rules. Opponent starters must be explicitly classified and match the league's required starter count; the repository's aggregate is only populated when every reported starter has a projection. An unavailable/failed score refresh, missing aggregate or unknown lineup omits the margin instead of implying zero or an advantage. A cached successful snapshot remains usable during ordinary refresh; the number updates when new data arrives.

If MFL has not published the week's matchup starters yet (including its preseason live-scoring gap), the owner's projection can be visible without a comparison. Do not substitute a guessed opponent lineup or score. Confirm the live matchup/projection comparison in the Week 1 owner check below.

## Verification

An independent iOS design-review agent inspected native screenshots at the owner's request. Its recommended revision aligned the card with the roster, reduced the margin's visual weight, named the full opponent and removed the status capsule. This was an AI-assisted design review, not a human usability study. Adjacent player-row truncation at maximum text sizes remains a separate accessibility issue in the release gate.

Model tests cover exact home/away ownership, draft updates, unchanged saved totals/actual scores, session/week isolation, missing and nonfinite projections, incomplete/duplicate/unknown starters, no matchup/doubleheaders, direction and rounded zero. Native Preview journeys cover the relocated status, green-to-orange substitution without submission and maximum Dynamic Type. An explicit DEBUG-only Preview fixture reproduces Current lineup with per-player kickoff locks; connected mode never uses that fixture.

Live owner check: compare both teams' Week 1 projected starters with MFL, edit an intended starter and confirm the margin responds, then review/submit only if desired. Passing synthetic journeys does not certify a live game week.
