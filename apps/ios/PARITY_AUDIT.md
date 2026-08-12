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
- [ ] Device preview/clock/lock screen
- [ ] Gyro controls
- [ ] Timeline ruler/playhead/tree/zoom/repeat/autoreverse/resize/snapping
- [ ] Geometry inspector
- [ ] Content inspector
- [ ] Text inspector
- [ ] Gradient inspector
- [ ] Image inspector
- [ ] Video inspector
- [ ] Emitter inspector
- [ ] Replicator inspector
- [ ] Filters inspector
- [ ] Compositing inspector
- [ ] Animations inspector/keyframes/bulk input/export — website control set implemented; awaiting full iOS CI verification.
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

- `.tendies` picker no longer exposes generic ZIP.
- Native-only JSON shortcut removed from `.ca` import.
- Website-style import type and direct-link controls applied.
- Mobile Add Layer hides Replicator/Liquid Glass like the website.
- Mobile state menu is Base/Locked/Unlock/Sleep like the website.
- Settings shortcut wording aligned with website.
- GIF video extraction uses the website's fixed 15 fps timing semantics.
- `.ca` and `.tendies` UTTypes/document types registered for native opening.
- Opening documents in place enabled.
- Full Layers panel restored from the last green implementation before applying mobile-only deltas.
- Animation inspector now mirrors website-supported key paths, duplicate filtering, gradient-only `colors`, empty new animations, current-value keyframes, custom key times, duration/loop/repeat/advanced controls, typed value editors, Bulk text plus `.txt/.csv` import, value export, and removal; CI verification pending.
