# Starter and FLEX swaps — 0.3.5 (13)

The replacement picker includes eligible bench players and other starters. It separates them into **Bench** and **Already starting**, sorts each group by projection, and labels each starter's current slot.

Keep visible copy minimal: short titles and player/slot arrows. Per-option arrows show the actual destinations instead of a paragraph explaining every possible outcome. VoiceOver retains explicit move descriptions. Storage and API details belong in developer documentation, not in the lineup picker.

- Fixed QB/RB/WR/TE slots offer players at that NFL position, including eligible FLEX starters.
- FLEX uses the league's position limits, not the current occupant's NFL position. Standard FLEX never adds a QB unless the league allows an extra QB.
- Compatible starters swap slots without benching either player. Two FLEX starters can swap even when their NFL positions differ.
- If a move into FLEX would leave an incompatible fixed slot, a second screen asks who should fill it. Choose an eligible bench player, or an eligible player from the other FLEX slot for a three-starter rotation.
- The second screen stages the move without editing the lineup. Back, Cancel, or dismiss leaves the original draft intact. Both changes apply together only after an eligible replacement is selected.
- Every selection rechecks league rules, slot assignments, account/week, locks, unique roster IDs, conflicts and edit availability. Promoting a bench tiebreaker clears that tiebreaker and requires another selection before submitting.

## Local slot placement and MFL

MFL's lineup API accepts starter IDs, not named FLEX assignments. The app therefore persists chosen slot placement with its private, team/year/week-scoped draft. Merely exchanging existing starters does **not** trigger a league write or a submit button. Replacing a starter with a bench player still requires Review & submit.

Placements survive refresh, relaunch and confirmed submission. Restored placements must still match the roster, starter set and current position rules; invalid or outdated placements fall back to the league-derived layout. Older saved drafts without slot placement remain readable. Live scoring continues to derive its slots from the server's starter set; it does not display an unsubmitted lineup draft.

## Regression coverage

`StarterSlotSwapTests` covers RB/WR/TE ↔ FLEX, FLEX ↔ FLEX, cross-position bench replacements, three-starter rotations, starter membership and count, tiebreakers, locked players, duplicate IDs, rule changes, stale requests, private draft persistence, confirmed submission through an in-memory repository, and old-draft migration.

Native UI journeys cover finding bench/FLEX replacements, swapping and reversing RB/FLEX placement, canceling a cross-position move, completing its second step, and reviewing the resulting lineup. Existing QB, FLEX and two-week offline journeys are also exercised. QA uses preview data and in-memory repositories, never live lineup submissions.

September 6 verification: the full app unit suite plus five lineup UI journeys passed (92 test functions; 117 executions including parameterized cases), with no failures or runtime warnings. The final copy/layout changes are additionally checked by the two new native swap journeys and retained screenshots.

## UI polish — 0.3.6 (14)

Removed storage-specific and redundant save footers from both replacement screens. The existing review, submission and authoritative MFL starter readback remain unchanged. The shared calendar control explicitly shows its icon and selected week, including in the Lineup toolbar; selecting another week updates the visible label.

Scores uses the same week control at top right, with Settings at top left. Live status remains beside the last-updated indicator above the matchups.
