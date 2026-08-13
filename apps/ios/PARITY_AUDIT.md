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
- [ ] States panel/View All/appearance split
- [ ] Settings panel/shortcuts/appearance/guides/onboarding reset
- [ ] Onboarding target highlighting and placement
- [ ] Canvas preview/pan/zoom/selection/handles/guides
- [ ] Device preview/clock/lock screen — website state machine/timings, Light/Dark split, depth effect, status/home chrome, gestures, and sleep timeline behavior implemented; full stacked iOS CI verification pending.
- [ ] Gyro controls
- [ ] Timeline ruler/playhead/tree/zoom/repeat/autoreverse/resize/snapping — website component and hardware Shift 0.5s resize snapping implemented; full stacked iOS CI verification pending.
- [ ] Geometry inspector — website animation locks, align target/actions, percentage resize controls, scale control, X/Y/Z rotation controls, anchor-point modes, state restrictions, and perspective behavior implemented; full stacked iOS CI verification pending.
- [ ] Content inspector
- [ ] Text inspector
- [ ] Gradient inspector
- [ ] Image inspector
- [ ] Video inspector
- [ ] Emitter inspector
- [ ] Replicator inspector
- [ ] Filters inspector
- [ ] Compositing inspector
- [x] Animations inspector/keyframes/bulk input/export — website control set implemented and verified by normal iOS CI run #110.
- [ ] Gyro inspector
- [ ] Blur editor
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
- Animation inspector mirrors website-supported key paths, duplicate filtering, gradient-only `colors`, empty new animations, current-value keyframes, custom key times, duration/loop/repeat/advanced controls, typed value editors, Bulk text plus `.txt/.csv` import, value export, and removal; run #110 passed simulator tests, device archive, package verification, and IPA upload.
- Timeline mirrors website ruler/tree/playhead/zoom/label-resize/repeat/autoreverse/speed-aware bars/duration-resize behavior and hardware Shift 0.5s snapping.
- Device Preview mirrors website Locked/Unlock/Sleep interactions, 50% swipe threshold, 200/300/500 ms transition timings, side-button/tap wake behavior, Light/Dark appearance split, clock depth ordering, live clock/date/status chrome, unlocked dock, and sleep timeline pause.
- Geometry inspector mirrors the website's conditional animation locks, Canvas/Parent alignment controls, optional percentage resize controls, 0–400% scale control, X/Y/Z rotation controls, 3×3/custom anchor controls, state-transition restrictions, and perspective control.
