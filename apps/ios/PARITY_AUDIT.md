# CAPlayground Website → Native iOS Parity Audit

This audit treats the website source as the specification. A checked item means the corresponding native implementation was compared against the website for route/control coverage, important defaults/disabled states, and data/import/export behavior, and the consolidated native tree passed iOS compilation/testing. It does **not** mean an automated screenshot pixel-diff has been completed.

## Validation baseline

- Consolidated staging validation: GitHub Actions run **#205**.
- Website/native companion API type-check: **passed**.
- iOS Simulator build-for-testing: **passed**.
- Native XCTest suite: **passed**.
- Unsigned arm64 iPhoneOS archive: **passed**.
- IPA package verification and artifact upload: **passed**.
- Auth provider redirects return directly to `caplayground://...`; provider login/linking does not depend on a CAPlayground web auth page.
- Local projects/assets are available without Supabase/Drive network access.

## Routes

- [x] `/` Home — hero, navigation behavior, live GitHub metrics, responsive bento composition, website example wallpaper actions, growth metrics, Most Downloaded wallpaper, footer.
- [x] `/projects` — search/filter/sort/grid/list, creation/device bounds/gyro, import modes, link import, select/bulk delete, Drive sync/download/delete, native `caplayground://projects` query-intent equivalents.
- [x] `/editor/[id]` — native Editor shell and editor subsystems.
- [x] `/wallpapers` — gallery/search/sort/stats/details/download/Pocket Poster/Open in Editor/copy link/submission/footer and native `caplayground://wallpapers` intents.
- [x] `/tendies-check` — `.tendies`-only import/drop, CA/remix inspection, file/type/tree/assets/video results.
- [x] `/signin` — email/password, Google/GitHub/Discord, theme/legal controls.
- [x] `/forgot-password` — native reset-link flow.
- [x] `/reset-password` — native two-field reset flow with 8-character minimum.
- [x] `/auth/success` — session verification, username completion, provider/email summary, Continue/Create Project/Dashboard/Sign out.
- [x] `/account` — account fields, OAuth-managed restrictions, provider link/unlink, password/account actions.
- [x] `/dashboard` — submissions/status sync, cloud projects, Drive actions, account options.
- [x] `/contributors` — contributor API/stats/cards/CTA/nav/footer.
- [x] `/roadmap` — month controls/cards/statuses/nav/footer.
- [x] `/privacy` — standalone Back/theme/paper shell, policy text, support/cross-policy/Google Privacy links.
- [x] `/tos` — standalone Back/theme/paper shell, terms text, support/cross-policy links.
- [x] `/docs` — website is an external documentation redirect; native intentionally links to the same documentation instead of inventing a screen.

## Shared website shell

- [x] Responsive website navigation and top/scrolled presentation.
- [x] Desktop signed-in account menu: Dashboard + Sign out.
- [x] Mobile signed-in Account/Dashboard behavior.
- [x] Sign-in vs Projects CTA behavior.
- [x] Theme toggle.
- [x] Website footer CTA/resources/community/legal links where the website uses the shared footer.

## Editor shell and interaction

- [x] Menu bar, active CA, Background visibility, panel toggles, save state/manual save, Settings, Export.
- [x] Mobile bottom bar, Canvas/Panels, CA selector, Add Layer and Base/Locked/Unlock/Sleep controls.
- [x] Layers tree/root, collapse, visibility, selection/multiselect, rename, duplicate, delete, nested drag/drop and reorder/front/forward/backward/back.
- [x] Canvas preview, selection, pan/zoom, resize/rotation, state-aware editing and snapping.
- [x] States/View All/appearance split and transition export behavior.
- [x] Settings, density, snapping, preview settings, shortcut list, panel widths and onboarding reset.
- [x] Target-highlight onboarding for Layers/States/Canvas/Inspector/Settings.
- [x] Lock-screen/device preview state machine, Light/Dark split, depth ordering, side-button/tap/swipe behavior and website transition timings.
- [x] Timeline ruler/playhead/tree/collapse/zoom/repeat/autoreverse/speed-aware bars/duration resize and Shift 0.5s snapping.
- [x] Hardware keyboard shortcut surface.

## Inspector / layer controls

- [x] Geometry — animation locks, Canvas/Parent alignment, percentage resize, scale, XYZ rotation, anchors, state restrictions, perspective.
- [x] Compositing — blend modes, opacity, Content cross-link, corner radius, Base-State clipping restrictions.
- [x] Content — gradient exclusions, background/border behavior and non-Base-state restrictions.
- [x] Text — text/font controls, alignment/wrapping and state restrictions.
- [x] Gradient — type, endpoint percentage controls, colors/opacities, add/remove.
- [x] Image — preview/replace/reset bounds, draggable crop/corner handles/5% minimum/maintain-bounds, destructive Blur.
- [x] Video — conversion settings, read-only metadata, state-sync children/overrides and sync-aware controls.
- [x] Emitter — layer speed/state restrictions, image-backed cells, advanced cell properties/color/RGB modulation.
- [x] Replicator — instance count/transform/delay constraints and helper copy.
- [x] Filters — six website filters/defaults, unique names, parameterless Invert, numeric/Hue editors, enable/remove.
- [x] Animations — supported key paths, duplicate filtering, gradient colors, typed keyframes, current-value Add, custom key times, repeat/autoreverse, Bulk text + `.txt/.csv`, export/remove.
- [x] Gyro — website dictionary controls plus root wallpaper parallax/property-group serialization/import reconstruction.

## Import/export, files and persistence

- [x] `.ca` archive/package/ZIP import behavior.
- [x] `.tendies` import behavior.
- [x] Direct `.tendies` URL import with name/creator metadata.
- [x] `.ca` and `.tendies` iOS UTType/document registration, Files/Share Sheet/Open In and opening in place.
- [x] Image types: PNG/JPEG/JPG/WebP/BMP/SVG; GIF routes through video conversion.
- [x] Video/GIF conversion, website fixed 15-fps GIF semantics, 15/30/60 fps selection and frame asset generation.
- [x] Animation Bulk `.txt`/`.csv` input.
- [x] `.ca` export ZIP structure, CAML/assets/license selection.
- [x] `.tendies` export/template/assets/license selection.
- [x] Per-document asset scoping and same-name asset collision round-trip.
- [x] States/transitions, typed animations, gradients, filters, emitter properties and angle unit conversion round-trip.
- [x] Wallpaper root `wallpaperBackgroundAssetNames`, `wallpaperFloatingAssetNames`, `wallpaperParallaxGroups`, `wallpaperPropertyGroups` serialization/import.
- [x] Local atomic project persistence/offline editing.
- [x] Google Drive list/connect/sync/update/download/delete/bulk-delete/disconnect behavior.

## Native tests / regression coverage

- [x] Archive/CAML model round-trip coverage.
- [x] Same-named per-document asset collision preservation.
- [x] Advanced emitter fields and degree↔radian behavior.
- [x] Video state-sync children/override round-trip.
- [x] Gyro wallpaper parallax/property groups and legacy non-wallpaper gyro round-trip.
- [x] State counterpart filling and six website default transitions.
- [x] Filter names and parameterless Invert semantics.
- [x] CI executes XCTest on an available iPhone Simulator before device archiving.

## Remaining verification caveat

The conversion has been source-audited and behavior/serialization tested to the point required for the consolidated port. The remaining thing **not** claimed by this audit is automated screenshot-by-screenshot pixel-diff verification against every responsive website breakpoint. Any future visual discrepancy found from device/simulator screenshots should be treated as a parity bug, not as permission to redesign the website UI.
