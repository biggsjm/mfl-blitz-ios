# App icon brief

The checked-in icon is original artwork generated for MFL Blitz. It does not use the MFL, NFL, or any team logo.

## Final generation prompt

> Use case: logo-brand. Asset type: 1024×1024 iOS app icon master artwork for a native fantasy-football companion called MFL Blitz. Primary request: an original bold symbol combining a simplified American-football ball silhouette with a fast diagonal play-route or lightning motion cut, communicating game-day speed and lineup control. Style/medium: minimal vector-like flat geometric mark, premium indie iOS app aesthetic, crisp strong silhouette, subtle tactile depth only through restrained lighting. Composition/framing: one large centered full-bleed icon composition with generous optical padding; artwork must remain legible at 29 px. Color palette: deep midnight navy background, vivid field-lime focal mark, small warm off-white highlight. Constraints: square image; opaque edge-to-edge background; no rounded-corner mask; no transparency; no text; no letters; no numbers; no NFL shield; no team logos; no MFL logo; no trademarks; no watermark; no mockup; no phone frame; no tiny details. Avoid: photorealistic football, gradients that reduce small-size clarity, chrome, mascots, stadium scene, generic clip art.

The master is stored at `docs/app-icon-source.png`; production renditions are in the app asset catalog.

## Lineup tab — 0.3.4 (12)

The Lineup tab uses an original monochrome football play diagram: two player circles, a straight route on the right, and an angled left route crossing over it, both ending in arrows. A small break in the straight route clarifies the crossing at tab-bar size. `LineupPlay.imageset` contains a 25-point SVG with rounded strokes and preserved vector representation. Template rendering inherits the native tab bar's unselected and selected colors; the existing “Lineup” text remains its visible and accessible label. The tab's tap target and navigation behavior are unchanged.

Asset and native UI tests verify bundled size, template tinting, the accessible label, selection changes, and a minimum 44-point hit area. Selected and unselected tab-bar screenshots are retained in the test result bundle.

In 0.3.6 (14), the right-hand route and its player circle move two SVG units left. The underpass gap follows the new intersection, increasing separation between the arrowheads without changing the asset size.
