# FORK.md — patches/1.58.0 divergence ledger

This file records every change carried in this fork relative to upstream SkipUI 1.58.0 (tag `1.58.0`, commit `1901924`). It is the canonical place to check what has diverged, how to verify each fix, and when a fix can be dropped.

**Integration branch:** `patches/1.58.0`
**Fork tag:** `1.58.0+fixes.1` (= `d518f5c543b147815f1ec2922b8160e1fe8f4774`)
**App pinning rule:** pin the app's SkipUI dependency to the annotated tag `1.58.0+fixes.1`, not to the `patches/1.58.0` branch HEAD. Tags are stable; the branch HEAD advances as new fixes land.

**Drop rule:** when a fix is merged upstream, rebase `patches/1.58.0` onto the next upstream tag, drop the fix commit(s) for that fix, and re-run the dual-side suite before advancing the app's pin.

---

## Fix 1 — IgnoresSafeAreaLayout `Constraints.Infinity` overflow crash

**Defect:** `IgnoresSafeAreaLayout` in `ComposeLayouts.swift` performs plain integer arithmetic to expand constraints by the safe-area inset. If an unbounded constraint (`Constraints.Infinity` = `Int.MAX_VALUE = 2_147_483_647`) reaches this path with a positive expansion (e.g., the navigation-bar inset), the addition wraps to a large negative value; `Constraints.copy()` with a negative max throws `IllegalArgumentException` mid-measure — a hard crash.

**Evidence status:** deterministic device crash captured 2026-07-10 on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation. The production app carried a contemporaneous workaround comment (background `.ignoresSafeArea()` deliberately omitted because "double-nesting crashes"); reverting that single modifier under stock skip-ui 1.57.0 (the guarded code is unchanged between 1.57.0 and 1.58.0) crashes on the first sheet open with the captured trace at the guarded `ComposeLayouts` lines (ComposeLayouts.kt:239 / :235 / :128), and identical source survives on this fork (and renders the intended edge-to-edge background). Trigger chain (all three required): sheet presentation delivering `Constraints.Infinity` via `TargetViewLayout`'s intrinsic-height pass → the `NavigationStack` scaffold's own `IgnoresSafeAreaLayout` → a second nested `IgnoresSafeAreaLayout` from `.ignoresSafeArea()` on the content background. Earlier non-reproductions (the MRE snippet on the API-34 AVD and on the A17; crash-free API-36/37 emulator sessions exercising other surfaces of the same MRE app; Firebase Test Lab production-app sheet runs (Galaxy S22, Pixel 10 Pro); and the production-app A/B at stock 1.58.0 with the workaround in place — see `EVIDENCE.md`) are all explained: the trigger was absent, either worked around at the app level or bounded away by the presentation root in minimal compositions. The minimal MRE snippet still does not crash. The guard eliminates the class by construction, at zero cost on finite constraints.

**Files touched:** `Sources/SkipUI/SkipUI/Compose/ComposeLayouts.swift`

**Fix branch:** `fix/ignores-safe-area-constraint-overflow`
**Fix commit:** `73e7a54` — `fix: saturate Constraints.Infinity in IgnoresSafeAreaLayout to prevent integer-overflow crash on Android`
**Test commit:** `4be0dbc` — `test: add regression tests for IgnoresSafeAreaLayout constraint-overflow fix`

**Upstream PR placeholder:** _(pending submission)_

---

## Fix 2 — NavigationStack hidden-toolbar safe-area inset double-application

**Defect:** When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the Compose layout falls back to `WindowInsets.safeDrawing.calculateTopPadding()` as content padding even though the bar height is zeroed. If the parent layout already compensates for the system inset, the gap is double-counted, appearing as a blank band below the status bar. Measured on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation: stock content area top `y=200 px`, fork content area top `y=100 px`, delta = 100 px = 1× status-bar height (35.6 dp at 2.8125 px/dp). Production-app A/B on the same device: Settings surface y=345 → y=245 (Δ=100 px); Firebase Test Lab directional corroboration: Galaxy S22 (SC-51C, One UI, API 36) Δ=44 px, Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) Δ=40 px (smaller because transparent/gesture insets are smaller).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/hidden-toolbar-safe-area-inset`
**Fix commit:** `d86ea68` — `fix: suppress safe-area inset fallback in NavigationStack when toolbar is explicitly hidden`
**Test commit:** `5e14c03` — `test: add regression tests for NavigationStack hidden-toolbar safe-area guard`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_2a.md)_

---

## Fix 3 — NavigationStack pushed-destination bottom inset dead band

**Defect:** When a `NavigationStack` is embedded inside a panel layout (e.g., a `VStack` with a custom tab bar below the navigation content), pushed destinations display a dead band at the bottom equal to one navigation-bar height. The `IgnoresSafeAreaLayout` adjacency check correctly returns `{}` for the bottom edge (the stack is not adjacent to the system nav-bar boundary), but the initial candidate edge set `ignoresSafeAreaEdges = [.bottom]` was passed into `NavigationEntryArguments` instead of the closure's actual-expanded-edges result. `RenderEntry`'s bottom-padding guard then applied navigation-bar inset padding regardless. Samsung Galaxy A17 navigation bar measures 135 px (48 dp at 2.8125 px/dp); this is the expected dead-band size for affected layouts.

**Evidence status:** confirmed at app scale — production-app A/B on the A17: stock dead band 310 px vs fork 175 px (Δ=135 px = 1× nav bar), with directional Firebase Test Lab corroboration on Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation: fork content extends 55 px further); the Galaxy S22 (SC-51C, One UI, API 36) run was null on this metric this session (content terminated before the affected zone). The isolated MRE shows zero stock/fork differential on all five tested environments plus two bisect rounds (the adjacency check already returns `{}` in both builds at minimal composition depth; the trigger is composition-scale — a panel/TabView layout pushing the NavigationStack off the nav-bar boundary).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/pushed-destination-bottom-inset`
**Fix commit:** `b2f7d58` — `fix: pass actual expanded edges into NavigationEntryArguments to correct pushed-destination bottom inset`
**Test commit:** `f40a9c5` — `test: add regression tests for NavigationStack pushed-destination bottom-inset fix`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_pushed-destination-bottom-inset.md)_

---

## Fix 4 — `.navigationBarTitleDisplayMode(.inline)` ignored on non-scrollable roots

**Defect (analysis-derived):** Applying `.navigationBarTitleDisplayMode(.inline)` to a `NavigationStack` root that is a non-scrollable view (`VStack`, `ZStack`, `Color`, etc.) can render the default large style instead. The mechanism is a composition-scope issue: `TopAppBarDefaults.pinnedScrollBehavior()` and `exitUntilCollapsedScrollBehavior()` each call `rememberTopAppBarState()` internally. With a single ternary expression selecting between them, only one remember slot is ever allocated; switching branches orphans the slot and creates a fresh (indeterminate) state on the recomposition that delivers the inline preference. The condition requires the preference to arrive after initial composition; when it arrives before the first rendered frame (e.g., `ScrollView` roots, minimal apps), the ternary form behaves correctly.

**Evidence status:** the weakest of the five — no runtime stock/fork differential captured in any recorded environment (isolated MRE: zero delta on three emulator API levels and the A17; app-level A/B: no surface exercising the `.inline` switching transition). Substantiated by Compose remember-slot semantics (a timing-race hypothesis: the preference arriving after first composition), the generated-Kotlin diff, and a JUnit model test; the pre-creation form is strictly safer and behavior-identical where the ternary already worked. Recommend submitting bundled with Fix 3 or last.

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/inline-title-nonscrollable-root`
**Fix commit:** `5170538` — `fix: pre-create both TopAppBar scroll behaviors at composition scope`
**Test commit:** `9c59fb3` — `test: add regression tests for NavigationStack inline title on non-scrollable roots`

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_inline-title-nonscrollable-root.md)_

---

## Fix 5 — `LocalRippleConfiguration` not propagating to `Button` clickable indication

**Defect:** Setting `LocalRippleConfiguration = null` (or a custom configuration) on a container view does not suppress or customise the ripple on child `Button` taps. `.clickable()` without an explicit `indication` parameter resolves `LocalIndication.current`, which in Material 3 is the M1 ripple (`androidx.compose.material.ripple`). The M1 ripple reads `LocalRippleTheme`, not `LocalRippleConfiguration` (M3). Scope: transpiled-path only. The native SwiftFuse path does not use this `.clickable()` call and `LocalRippleConfiguration` does not cross the JNI bridge.

**Evidence status:** code inspection + JUnit model test only; no runtime observation of the defect or the fix exists in the evidence record (all recorded environments were SkipFuse-native builds, which structurally cannot exhibit it — stock and fork provably identical on this path by APK diff). Behavioral confirmation requires a skipstone-transpiled app.

**Files touched:** `Sources/SkipUI/SkipUI/Controls/Button.swift`

**Fix branch:** `fix/button-ripple-configuration`
**Fix commit:** `e87c50e` — `fix: propagate LocalRippleConfiguration to Button clickable indication`
**Test commit:** `696ec8a` — `test: add regression tests for Button LocalRippleConfiguration propagation`

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
| `MREs.md` | Minimal reproduction example for Fix 2, plus a non-crashing regression surface for Fix 1 (the Fix 1 snippet exercises the guarded path but does not reproduce the crash; the reproduction is the workaround-reverted device A/B) |
| `scripts/rebase-onto-upstream.sh` | Rebase helper — see below |
| `EVIDENCE.md` (in `~/Documents/skipui-mre/evidence/`) | Evidence index: chronological device / emulator / Firebase Test Lab measurement record, with a current-status TL;DR at the top |

---

## Rebase log

### 1.57.0 → 1.58.0 (2026-07-09)

- **Upstream range:** `9f4345c..1901924` (7 upstream commits)
- **Upstream files changed:** `Color.swift`, `ContextMenu.swift`, `List.swift`, `DatePicker.swift`, `Picker.swift`, `EnvironmentValues.swift`, `TextField.swift` — zero overlap with our five patched files
- **Conflicts:** none
- **Suite result:** PASS — `JUNIT SUITES 9 TESTS 104 PASSED 102 (98.0%) FAILED 0 SKIPPED 2 TIME 128.56` (matches 1.57.0 baseline: 104 tests, 0 failures, 2 upstream Robolectric skips). The ledger in `VERIFICATION.md` (TIME 126.28) is a separate run of the same suite on this branch — identical composition and counts; wall-clock TIME varies run-to-run.

---

## Rebase procedure

Use `scripts/rebase-onto-upstream.sh <new-upstream-tag>` to advance the integration branch. The script fetches the upstream tag, rebases `patches/1.58.0` onto it, runs the dual-side suite, and prints the JUNIT summary. It refuses to exit cleanly on suite failure. Drop fix commits whose upstream PRs have been merged before running the rebase.
