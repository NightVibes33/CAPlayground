# CAPlayground Website → Native iOS Parity Audit

This file is an engineering checklist for the native conversion. A surface is only marked **verified** after its website source, native source, behavior/defaults/disabled states, persistence/import/export semantics, and iOS CI build have been checked.

## Routes

- [ ] `/` Home
- [ ] `/projects` Projects/import/cloud actions
- [ ] `/editor/[id]` Editor shell and all editor components
- [ ] `/wallpapers` Gallery and submission
- [ ] `/tendies-check` Tendies checker
- [ ] `/signin` Sign in/sign up/OAuth
- [ ] `/forgot-password` Forgot password
- [ ] `/reset-password` Reset password
- [ ] `/auth/success` Auth callback/success behavior
- [ ] `/account` Account/provider linking/actions
- [ ] `/dashboard` Dashboard/submissions/cloud project actions
- [ ] `/contributors` Contributors
- [ ] `/roadmap` Roadmap
- [ ] `/privacy` Privacy
- [ ] `/tos` Terms
- [x] `/docs` is an external redirect on the website; do not invent a native Docs page.

## Editor

- [ ] Menu bar
- [ ] Mobile bottom bar
- [ ] Layers panel/context menu/reorder/multi-select/visibility
- [ ] States panel/View All/appearance split — export counterpart filling and website default transitions implemented; consolidated CI pending.
- [ ] Settings panel/shortcuts/appearance/guides/onboarding reset
- [ ] Onboarding target highlighting and placement — actual Layers/States/Canvas/Inspector/Settings frames, website placements and navigation implemented; consolidated CI pending.
- [ ] Canvas preview/pan/zoom/selection/handles/guides
- [ ] Device preview/clock/lock screen — website state machine/timings, Light/Dark split, depth effect, status/home chrome, gestures, and sleep timeline behavior implemented; consolidated CI pending.
- [ ] Gyro controls
- [ ] Timeline ruler/playhead/tree/zoom/repeat/autoreverse/resize/snapping — website component and hardware Shift 0.5s resize snapping implemented; consolidated CI pending.
- [ ] Geometry inspector — website animation locks, align target/actions, percentage resize controls, scale control, X/Y/Z rotation controls, anchor-point modes, state restrictions, and perspective behavior implemented; Simulator CI passed on run #141; consolidated CI pending.
- [ ] Content inspector — website gradient exclusion, state-aware background color, Base-State-only background opacity/border controls, percentage input, and cross-link behavior implemented; Simulator CI passed on run #147; consolidated CI pending.
- [ ] Text inspector — website state restrictions, center fallback, four alignment controls, and wrap helper copy implemented; Simulator CI passed on run #147; consolidated CI pending.
- [ ] Gradient inspector — website type, 0–100% endpoint slider/input controls, color opacity display, add/remove controls implemented; Simulator CI passed on run #147; consolidated CI pending.
- [ ] Image inspector — replacement/reset/state restrictions plus website draggable crop rectangle/four corner handles/5% minimum/maintain-bounds behavior implemented; consolidated CI pending.
- [ ] Video inspector — read-only Frames/FPS/Duration, sync-aware Calculation/Auto Reverse controls, frame child generation, Locked/Unlock/Sleep Beginning/End defaults, and z-position state overrides implemented; Simulator CI passed on run #151; consolidated CI pending.
- [ ] Emitter inspector
- [ ] Replicator inspector — website field layout, 1–100 count, translation/rotation helper copy, and non-negative delay behavior implemented; consolidated CI pending.
- [ ] Filters inspector — website unique filter names persisted through CAML, parameterless Invert semantics, checkbox/remove controls, numeric fields and Hue knob implemented; consolidated CI pending.
- [ ] Compositing inspector — website percentage opacity input, Content cross-link, corner radius and Base-State-only clip behavior implemented; Simulator CI passed on run #147; consolidated CI pending.
- [x] Animations inspector/keyframes/bulk input/export — website control set implemented and verified by normal iOS CI run #110.
- [ ] Gyro inspector — website dictionary count/add/remove/title/axis/fixed-key-path/map controls plus root wallpaper style/parallax/property-group import/export implemented; consolidated CI pending.
- [x] Blur editor — website 0–50 px live preview, 1 px step, Cancel and Apply Blur behavior matched.
- [ ] Export dialog and success actions
- [ ] Video/GIF conversion

## Import/export and persistence

- [ ] `.ca` archive/folder/ZIP import semantics
- [ ] `.tendies` import semantics
- [ ] `.tendies` direct URL import
- [ ] image types: PNG/JPEG/JPG/WebP/BMP/SVG and GIF routing
- [ ] video/GIF frame conversion and timing
- [ ] `.ca` export structure/assets/license
- [ ] `.tendies` export/template/assets/license
- [ ] local offline project persistence and scoped assets
- [ ] Google Drive sync/conflict/bulk delete/progress flows
- [ ] Files/Share Sheet/Open In document registration

## Current strict fixes already applied in this audit

- `.tendies` checker picker and drag/drop now accept `.tendies` only, matching the website.
- Native-only JSON shortcut removed from `.ca` import.
- Website-style import type and direct-link controls applied.
- Mobile Add Layer hides Replicator/Liquid Glass like the website.
- Mobile state menu is Base/Locked/Unlock/Sleep like the website.
- Settings shortcut wording aligned with website.
- GIF video extraction uses the website's fixed 15 fps timing semantics.
- `.ca` and `.tendies` UTTypes/document types registered for native opening.
- Opening documents in place enabled.
- Full Layers panel restored from the last green implementation before applying mobile-only deltas.
- Reset-password UI and the underlying auth updater now enforce the website's 8-character minimum.
- OAuth success now includes username completion, provider/email account summary, Continue, Create a Project, Account Dashboard, and Sign out actions.
- Dashboard submission status sync uses the website `/api/wallpapers/sync` flow; submission preview is real looping MP4/MOV media; bulk cloud actions and website messaging are aligned.
- Gallery submission now opens the same submission surface for signed-in and signed-out users; signed-out state shows the website's Sign In Required content.
- Animation inspector mirrors website-supported key paths, duplicate filtering, gradient-only `colors`, empty new animations, current-value keyframes, custom key times, duration/loop/repeat/advanced controls, typed value editors, Bulk text plus `.txt/.csv` import, value export, and removal; run #110 passed simulator build, device archive, package verification, and IPA upload.
- Timeline mirrors website ruler/tree/playhead/zoom/label-resize/repeat/autoreverse/speed-aware bars/duration-resize behavior and hardware Shift 0.5s snapping.
- Device Preview mirrors website Locked/Unlock/Sleep interactions, 50% swipe threshold, 200/300/500 ms transition timings, side-button/tap wake behavior, Light/Dark appearance split, clock depth ordering, live clock/date/status chrome, unlocked dock, and sleep timeline pause.
- Geometry inspector mirrors the website's conditional animation locks, Canvas/Parent alignment controls, optional percentage resize controls, 0–400% scale control, X/Y/Z rotation controls, 3×3/custom anchor controls, state-transition restrictions, and perspective control.
- Compositing, Content, Text, and Gradient now use the website's controls/defaults and state-transition restrictions instead of native-only shortcuts.
- Video state-sync now generates native image frame children and z-position overrides equivalent to the website, while preserving stable UUID targets through CAML import/export.
- Gyro wallpaper export now emits root-level `wallpaperBackgroundAssetNames`, `wallpaperFloatingAssetNames`, `wallpaperParallaxGroups`, and `wallpaperPropertyGroups`; import restores property-group overrides and redistributes parallax dictionaries to their target layers by `layerName`.
- Non-wallpaper legacy nested gyro dictionaries remain round-trippable without changing website-correct wallpaper root serialization.
- Normal CA state export now fills missing counterpart overrides from Base State and emits the website's six default Locked/Unlock/Sleep transitions when no explicit transitions exist.
- Filter names now round-trip through CAML and parameterless `colorInvert` imports as value 0, matching the website.
- Native CI now executes the XCTest suite on a dynamically selected available iPhone Simulator before starting the unsigned arm64 archive.
- Added round-trip tests for Video state-sync, Gyro wallpaper parallax/property groups, state counterpart/default-transition export, filter names/Invert, plus retained legacy advanced-control coverage.
