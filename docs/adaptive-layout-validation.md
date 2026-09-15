# Adaptive layout validation — September 9, 2026

Build 0.6.1 (38) preserves the existing craft fixes and adds a regression journey for lineup continuity while available height changes. It does not introduce a separate Duo layout or guessed hinge dimensions.

The current checkout contained three older source copies named `AppModel 2.swift`, `ScoresView 2.swift`, and `MFLBlitzUITests 2.swift` inside Xcode synchronized groups. A baseline build failed because those copies were compiled alongside the current implementations. Target membership exceptions now exclude those three copies; their files and contents are preserved. The app and test targets build with the current implementations.

The native UI journey edits a synthetic Preview lineup, records its week and projected margin, rotates to a short landscape window, and verifies the same draft and reachable Review action. It opens the review, returns to portrait, verifies the same nine-starter confirmation, then cancels and verifies the unsaved draft remains. It performs no MFL submission. The first fixture accidentally replaced the selected bench tiebreaker and correctly failed lineup validation; the corrected fixture preserves that tiebreaker.

Current-SDK app/test compilation and the focused rotation journey passed on the iOS 18.4 iPhone 16 Pro simulator. Earlier production-code coverage remains 107 core and 224 app tests; those counts are prior-pass evidence, not a claim that all suites were rerun for this project-membership/test-only increment. Screenshot verification and phone installation are recorded in current status.

Actual Duo folding, changed vertical bar placement, reserved regions and presentation behavior still require the iOS 27.1 SDK/simulator or hardware. Current size/orientation tests establish continuity under supported APIs; they cannot certify an unavailable device runtime. Broad supported-device, VoiceOver and real game-week release checks remain open.
