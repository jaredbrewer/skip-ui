# FORK.md — patches/1.58.0 divergence ledger

This file records every change carried in this fork relative to upstream SkipUI 1.58.0 (tag `1.58.0`, commit `1901924`). It is the canonical place to check what has diverged, how to verify each fix, and when a fix can be dropped.

**Integration branch:** `patches/1.58.0`
**Fork tag:** `1.58.0+fixes.1`
**App pinning rule:** pin the app's SkipUI dependency to the annotated tag `1.58.0+fixes.1`, not to the `patches/1.58.0` branch HEAD. Tags are stable; the branch HEAD advances as new fixes land.

**Drop rule:** when a fix is merged upstream, rebase `patches/1.58.0` onto the next upstream tag, drop the fix commit(s) for that fix, and re-run the dual-side suite before advancing the app's pin.

---

## Fix 1 — IgnoresSafeAreaLayout `Constraints.Infinity` overflow crash

**Defect:** `IgnoresSafeAreaLayout` in `ComposeLayouts.swift` performs plain integer arithmetic to expand constraints by the safe-area inset. During sheet intrinsic-height measurement, Compose passes `Constraints.Infinity` (`Int.MAX_VALUE = 2_147_483_647`) as `maxWidth`/`maxHeight`. Adding any positive expansion (e.g., the navigation-bar inset) causes two's-complement wrap to a large negative value; `Constraints.copy()` with a negative `maxWidth` throws `IllegalArgumentException: maxWidth must be >= minWidth`. The crash is 100% reproducible on real hardware when opening any sheet containing `.ignoresSafeArea()` inside a `NavigationStack`. The crash does not reproduce on the AVD (SwiftShader constraint arithmetic differs) or in the minimal MRE on Android 16 (Compose BOM / intrinsic-measurement delta; see `EVIDENCE.md`).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/ComposeLayouts.swift`

**Fix branch:** `fix/ignores-safe-area-constraint-overflow`
**Fix commit:** `c1ec626` — `fix: saturate Constraints.Infinity in IgnoresSafeAreaLayout to prevent integer-overflow crash on Android`
**Test commit:** `397b799` — `test: add regression tests for IgnoresSafeAreaLayout constraint-overflow fix`

**Upstream PR placeholder:** _(pending submission)_

---

## Fix 2 — NavigationStack hidden-toolbar safe-area inset double-application

**Defect:** When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the Compose layout falls back to `WindowInsets.safeDrawing.calculateTopPadding()` as content padding even though the bar height is zeroed. If the parent layout already compensates for the system inset, the gap is double-counted, appearing as a blank band below the status bar. Measured on Samsung Galaxy A17 (SM-A176U1), Android 16: stock content area top `y=200 px`, fork content area top `y=100 px`, delta = 100 px = 1× status-bar height (35.6 dp at 2.8125 px/dp).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/hidden-toolbar-safe-area-inset`
**Fix commit:** `1efd7c5` — `fix: suppress safe-area inset fallback in NavigationStack when toolbar is explicitly hidden`
**Test commit:** `3a301a7` — `test: add regression tests for NavigationStack hidden-toolbar safe-area guard`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_2a.md)_

---

## Fix 3 — NavigationStack pushed-destination bottom inset dead band

**Defect:** When a `NavigationStack` is embedded inside a panel layout (e.g., a `VStack` with a custom tab bar below the navigation content), pushed destinations display a dead band at the bottom equal to one navigation-bar height. The `IgnoresSafeAreaLayout` adjacency check correctly returns `{}` for the bottom edge (the stack is not adjacent to the system nav-bar boundary), but the initial candidate edge set `ignoresSafeAreaEdges = [.bottom]` was passed into `NavigationEntryArguments` instead of the closure's actual-expanded-edges result. `RenderEntry`'s bottom-padding guard then applied navigation-bar inset padding regardless. Samsung Galaxy A17 navigation bar measures 135 px (48 dp at 2.8125 px/dp); this is the expected dead-band size for affected layouts.

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/pushed-destination-bottom-inset`
**Fix commit:** `91bdf77` — `fix: pass actual expanded edges into NavigationEntryArguments to correct pushed-destination bottom inset`
**Test commit:** `a538cf6` — `test: add regression tests for NavigationStack pushed-destination bottom-inset fix`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_pushed-destination-bottom-inset.md)_

---

## Fix 4 — `.navigationBarTitleDisplayMode(.inline)` ignored on non-scrollable roots

**Defect:** Applying `.navigationBarTitleDisplayMode(.inline)` to a `NavigationStack` root that is a non-scrollable view (`VStack`, `ZStack`, `Color`, etc.) has no effect — the title renders in the default large style. The fix is a composition-scope issue: `TopAppBarDefaults.pinnedScrollBehavior()` and `exitUntilCollapsedScrollBehavior()` each call `rememberTopAppBarState()` internally. With a single ternary expression selecting between them, only one remember slot is ever allocated; switching branches orphans the slot and creates a fresh (indeterminate) state on the recomposition that delivers the inline preference. The defect does not occur when the root is a `ScrollView` because the preference arrives before the first rendered frame.

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/inline-title-nonscrollable-root`
**Fix commit:** `e7462c6` — `fix: pre-create both TopAppBar scroll behaviors at composition scope`
**Test commit:** `bb9074a` — `test: add regression tests for NavigationStack inline title on non-scrollable roots`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_inline-title-nonscrollable-root.md)_

---

## Fix 5 — `LocalRippleConfiguration` not propagating to `Button` clickable indication

**Defect:** Setting `LocalRippleConfiguration = null` (or a custom configuration) on a container view does not suppress or customise the ripple on child `Button` taps. `.clickable()` without an explicit `indication` parameter resolves `LocalIndication.current`, which in Material 3 is the M1 ripple (`androidx.compose.material.ripple`). The M1 ripple reads `LocalRippleTheme`, not `LocalRippleConfiguration` (M3). Scope: transpiled-path only. The native SwiftFuse path does not use this `.clickable()` call and `LocalRippleConfiguration` does not cross the JNI bridge.

**Files touched:** `Sources/SkipUI/SkipUI/Controls/Button.swift`

**Fix branch:** `fix/button-ripple-configuration`
**Fix commit:** `f31f8e4` — `fix: propagate LocalRippleConfiguration to Button clickable indication`
**Test commit:** `827ce6d` — `test: add regression tests for Button LocalRippleConfiguration propagation`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_button-ripple-configuration.md)_

---

## Supporting files (not upstream candidates)

| File | Purpose |
|---|---|
| `FORK.md` | This file — divergence ledger |
| `VERIFICATION.md` | Verification plan and fails-at-stock matrix |
| `PR_DRAFT_2a.md` | Draft PR for Fix 2 |
| `PR_DRAFT_2c.md` | Draft PR for Fix 1 |
| `PR_DRAFT_pushed-destination-bottom-inset.md` | Draft PR for Fix 3 |
| `PR_DRAFT_inline-title-nonscrollable-root.md` | Draft PR for Fix 4 |
| `PR_DRAFT_button-ripple-configuration.md` | Draft PR for Fix 5 |
| `MREs.md` | Minimal reproduction examples for Fixes 1 and 2 |
| `scripts/rebase-onto-upstream.sh` | Rebase helper — see below |
| `EVIDENCE.md` (in `~/Documents/skipui-mre/`) | Device measurement log (Samsung Galaxy A17) |

---

## Rebase log

### 1.57.0 → 1.58.0 (2026-07-09)

- **Upstream range:** `9f4345c..1901924` (7 upstream commits)
- **Upstream files changed:** `Color.swift`, `ContextMenu.swift`, `List.swift`, `DatePicker.swift`, `Picker.swift`, `EnvironmentValues.swift`, `TextField.swift` — zero overlap with our five patched files
- **Conflicts:** none
- **Suite result:** PASS — `JUNIT SUITES 9 TESTS 104 PASSED 102 (98.0%) FAILED 0 SKIPPED 2 TIME 128.56` (matches 1.57.0 baseline: 104 tests, 0 failures, 2 upstream Robolectric skips)

---

## Rebase procedure

Use `scripts/rebase-onto-upstream.sh <new-upstream-tag>` to advance the integration branch. The script fetches the upstream tag, rebases `patches/1.58.0` onto it, runs the dual-side suite, and prints the JUNIT summary. It refuses to exit cleanly on suite failure. Drop fix commits whose upstream PRs have been merged before running the rebase.
