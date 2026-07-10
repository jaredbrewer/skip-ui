# FORK.md — patches/1.58.0 divergence ledger

This file records every change carried in this fork relative to upstream SkipUI 1.58.0 (tag `1.58.0`, commit `1901924`). It is the canonical place to check what has diverged, how to verify each fix, and when a fix can be dropped.

**Integration branch:** `patches/1.58.0`
**Fork tag:** `1.58.0+fixes.1` (= `d518f5c543b147815f1ec2922b8160e1fe8f4774`)
**App pinning rule:** pin the app's SkipUI dependency to the annotated tag `1.58.0+fixes.1`, not to the `patches/1.58.0` branch HEAD. Tags are stable; the branch HEAD advances as new fixes land.

**Drop rule:** when a fix is merged upstream, rebase `patches/1.58.0` onto the next upstream tag, drop the fix commit(s) for that fix, and re-run the dual-side suite before advancing the app's pin.

**Shipping set (as of 2026-07-10):** three fixes — 2c (`IgnoresSafeAreaLayout` overflow), 2a (hidden-toolbar safe-area inset), and W3 (pushed-destination bottom inset). An adversarial review withdrew W4 (inline-title) and W5 (button-ripple) — their production changes are reverted, tests deleted, and `fix/*` branches removed. See "Withdrawn fixes" below.

**PENDING:** a re-tag to `1.58.0+fixes.2` and the app dependency repin are **not yet done** — deliberately batched until 2a's device verification (owned by another agent) resolves keep-or-rework. The tag still points at `1.58.0+fixes.1`; the branch HEAD has since advanced (W4/W5 reverts + 2c/W3 test rebuild).

---

## Fix 1 — IgnoresSafeAreaLayout `Constraints.Infinity` overflow crash

**Defect:** `IgnoresSafeAreaLayout` in `ComposeLayouts.swift` performs plain integer arithmetic to expand constraints by the safe-area inset. If an unbounded constraint (`Constraints.Infinity` = `Int.MAX_VALUE = 2_147_483_647`) reaches this path with a positive expansion (e.g., the navigation-bar inset), the addition wraps to a large negative value; `Constraints.copy()` with a negative max throws `IllegalArgumentException` mid-measure — a hard crash.

**Evidence status:** deterministic device crash captured 2026-07-10 on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation. The production app carried a contemporaneous workaround comment (background `.ignoresSafeArea()` deliberately omitted because "double-nesting crashes"); reverting that single modifier under stock skip-ui 1.57.0 (the guarded code is unchanged between 1.57.0 and 1.58.0) crashes on the first sheet open with the captured trace at the guarded `ComposeLayouts` lines (ComposeLayouts.kt:239 / :235 / :128), and identical source survives on this fork (and renders the intended edge-to-edge background). Trigger chain (all three required): sheet presentation delivering `Constraints.Infinity` via `TargetViewLayout`'s intrinsic-height pass → the `NavigationStack` scaffold's own `IgnoresSafeAreaLayout` → a second nested `IgnoresSafeAreaLayout` from `.ignoresSafeArea()` on the content background. Earlier non-reproductions (the MRE snippet on the API-34 AVD and on the A17; crash-free API-36/37 emulator sessions exercising other surfaces of the same MRE app; Firebase Test Lab production-app sheet runs (Galaxy S22, Pixel 10 Pro); and the production-app A/B at stock 1.58.0 with the workaround in place — see `EVIDENCE.md`) are all explained: the trigger was absent, either worked around at the app level or bounded away by the presentation root in minimal compositions. The minimal MRE snippet still does not crash. The guard eliminates the class by construction, at zero cost on finite constraints.

**Files touched:** `Sources/SkipUI/SkipUI/Compose/ComposeLayouts.swift`

**Fix branch:** `fix/ignores-safe-area-constraint-overflow`
**Fix commit (integration branch):** `ab86216` — `fix: saturate Constraints.Infinity in IgnoresSafeAreaLayout to prevent integer-overflow crash on Android` (production, device-confirmed, unchanged)
**Test-rebuild commit:** `ee3dc52` — the original arithmetic test reimplemented the saturation locally (passed even if production reverted), tested the WIDTH axis while the crash is on maxHEIGHT, and its smoke omitted a presentation root (`_safeArea` nil → guarded block never ran). Replaced with `testIgnoresSafeAreaInfiniteMaxHeightMeasureDoesNotOverflow`, which drives the REAL measure lambda (synthetic non-zero `SafeArea` + `verticalScroll` infinite maxHeight). **Fail-at-stock verified in-harness:** with the saturation guard temporarily reverted, the test fails with `java.lang.IllegalArgumentException` (`Int.MAX_VALUE + 200` wraps negative → `Constraints.copy` throws mid-measure); with the guard, it passes — `JUNIT … FAILED 1` at stock vs `FAILED 0` on the fork, exactly one test flipping.

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_2c.md)_

---

## Fix 2 — NavigationStack hidden-toolbar safe-area inset double-application

**Defect:** When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the Compose layout falls back to `WindowInsets.safeDrawing.calculateTopPadding()` as content padding even though the bar height is zeroed. If the parent layout already compensates for the system inset, the gap is double-counted, appearing as a blank band below the status bar. Measured on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation: stock content area top `y=200 px`, fork content area top `y=100 px`, delta = 100 px = 1× status-bar height (35.6 dp at 2.8125 px/dp). Production-app A/B on the same device: Settings surface y=345 → y=245 (Δ=100 px); Firebase Test Lab directional corroboration: Galaxy S22 (SC-51C, One UI, API 36) Δ=44 px, Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) Δ=40 px (smaller because transparent/gesture insets are smaller).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/hidden-toolbar-safe-area-inset`
**Fix commit (integration branch):** `737d800` — `fix: suppress safe-area inset fallback in NavigationStack when toolbar is explicitly hidden`
**Test commit:** `a8c43cf` — the four hidden-toolbar tests (unchanged by this pass)

**Status:** fate PENDING a device test owned by another agent (keep-or-rework). This pass left the 2a production code and its tests untouched.

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_2a.md)_

---

## Fix 3 — NavigationStack pushed-destination bottom inset dead band

**Defect:** When a `NavigationStack` is embedded inside a panel layout (e.g., a `VStack` with a custom tab bar below the navigation content), pushed destinations display a dead band at the bottom equal to one navigation-bar height. The `IgnoresSafeAreaLayout` adjacency check correctly returns `{}` for the bottom edge (the stack is not adjacent to the system nav-bar boundary), but the initial candidate edge set `ignoresSafeAreaEdges = [.bottom]` was passed into `NavigationEntryArguments` instead of the closure's actual-expanded-edges result. `RenderEntry`'s bottom-padding guard then applied navigation-bar inset padding regardless. Samsung Galaxy A17 navigation bar measures 135 px (48 dp at 2.8125 px/dp); this is the expected dead-band size for affected layouts.

**Evidence status:** confirmed at app scale — production-app A/B on the A17: stock dead band 310 px vs fork 175 px (Δ=135 px = 1× nav bar), with directional Firebase Test Lab corroboration on Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation: fork content extends 55 px further); the Galaxy S22 (SC-51C, One UI, API 36) run was null on this metric this session (content terminated before the affected zone). The isolated MRE shows zero stock/fork differential on all five tested environments plus two bisect rounds (the adjacency check already returns `{}` in both builds at minimal composition depth; the trigger is composition-scale — a panel/TabView layout pushing the NavigationStack off the nav-bar boundary).

**Files touched:** `Sources/SkipUI/SkipUI/Containers/Navigation.swift`

**Fix branch:** `fix/pushed-destination-bottom-inset`
**Fix commit (integration branch):** `2e21386` — `fix: pass actual expanded edges into NavigationEntryArguments to correct pushed-destination bottom inset` (production, device-confirmed, unchanged)
**Test-rebuild commit:** `ee3dc52` — `testPushedDestinationRendersWithoutCrash` never pushed a destination. It now seeds the `NavigationStack` with a non-empty `NavigationPath` so a real destination is pushed and the `RenderEntry` bottom-padding path runs. Honest limitation: under Robolectric `WindowInsets.safeDrawing` is 0, so the pushed panel's bottom dead band is 0 in both stock and fork — a rendered geometry assertion cannot distinguish them here; the deterministic dead-band evidence remains the on-device production-app A/B (see below). The `testPushedDestinationAppliesBottomInsetOnce` adjacency model test is retained.

**Upstream PR placeholder:** _(pending submission — see PR_DRAFT_pushed-destination-bottom-inset.md)_

---

## Withdrawn fixes — W4 and W5 (reverted 2026-07-10, `56ce302`)

An adversarial review found both former fixes unnecessary/harmful. Their production changes are reverted, their regression tests deleted, and their `fix/*` branches removed (local + origin). The `PR_DRAFT_*` files are retained but banner-marked WITHDRAWN.

### W4 (was Fix 4) — `.navigationBarTitleDisplayMode(.inline)` on non-scrollable roots — WITHDRAWN

The former change pre-created both `TopAppBarDefaults.pinnedScrollBehavior()` and `exitUntilCollapsedScrollBehavior()` at composition scope. **Reason for withdrawal:** the app-bar TYPE (large vs inline `TopAppBar`) is selected from `isInlineTitleDisplayMode` **independently** of the pre-created scroll behaviors, so pre-creating both does NOT enable the first inline transition — that transition is already immediate. The only real effect is keeping both `TopAppBarState` slots alive simultaneously, a latent stale collapsed/overlap-offset risk when the display mode flips while the bar is scrolled. It was also the weakest of the five: no runtime stock/fork differential was captured in any recorded environment. Reverted `Sources/SkipUI/SkipUI/Containers/Navigation.swift` to the stock single-ternary `initialScrollBehavior`.

### W5 (was Fix 5) — `LocalRippleConfiguration` → `Button` clickable indication — WITHDRAWN

The former change read `LocalRippleConfiguration.current` at the `.clickable()` call site and passed `indication = null` when the M3 config was suppressed. **Reason for withdrawal:** redundant, and its premise is factually wrong for the resolved Material3 (≥ 1.3.0; 1.4.0 here). On Material3 ≥ 1.3.0, `MaterialTheme` (`ColorScheme.swift`) installs the **M3** ripple as `LocalIndication`, and that indication **already** reads `LocalRippleConfiguration` — it removes the ripple when the configuration is `null` and applies the configured color/alpha otherwise. **Stock `.clickable(onClick:enabled:)` therefore already honors `.material3Ripple { _ in nil }` and container-level `LocalRippleConfiguration` suppression on M3 ≥ 1.3.0.** The premise comment ("`LocalIndication` is the M1 ripple reading `LocalRippleTheme`") is wrong for material3 ≥ 1.3.0, and forcing `indication = null` would additionally discard any non-ripple custom indication a caller installed. Reverted `Sources/SkipUI/SkipUI/Controls/Button.swift` to the stock `modifier = modifier.clickable(onClick: action, enabled: isEnabled)` (imports `LocalIndication`/`remember` dropped too).

---

## Supporting files (not upstream candidates)

| File | Purpose |
|---|---|
| `FORK.md` | This file — divergence ledger |
| `VERIFICATION.md` | Verification plan and fails-at-stock matrix |
| `PR_DRAFT_2a.md` | Draft PR for Fix 2 (2a) |
| `PR_DRAFT_2c.md` | Draft PR for Fix 1 (2c) |
| `PR_DRAFT_pushed-destination-bottom-inset.md` | Draft PR for Fix 3 (W3) |
| `PR_DRAFT_inline-title-nonscrollable-root.md` | **WITHDRAWN** (W4) — banner-marked; retained for history |
| `PR_DRAFT_button-ripple-configuration.md` | **WITHDRAWN** (W5) — banner-marked; retained for history |
| `MREs.md` | Minimal reproduction example for Fix 2, plus a non-crashing regression surface for Fix 1 (the Fix 1 snippet exercises the guarded path but does not reproduce the crash; the reproduction is the workaround-reverted device A/B) |
| `scripts/rebase-onto-upstream.sh` | Rebase helper — see below |
| `EVIDENCE.md` (in `~/Documents/skipui-mre/evidence/`) | Evidence index: chronological device / emulator / Firebase Test Lab measurement record, with a current-status TL;DR at the top |

---

## Change log

### 2026-07-10 — adversarial-review cuts (W4/W5 withdrawn; 2c/W3 tests rebuilt)

- **Production reverts (`56ce302`):** W4 (`Navigation.swift`) and W5 (`Button.swift`) reverted to stock. See "Withdrawn fixes" above.
- **Test rebuild (`ee3dc52`):** 2c and W3 regression tests rebuilt to drive real production paths; W4/W5 tests deleted.
- **Branches removed:** `fix/inline-title-nonscrollable-root` and `fix/button-ripple-configuration` deleted local + origin.
- **Suite result:** PASS — `JUNIT SUITES 9 TESTS 97 PASSED 95 (98.0%) FAILED 0 SKIPPED 2 TIME 131.36` (was 104; −3 W4 tests, −3 W5 tests, −1 net from the 2c test rebuild; the 2 skips are the upstream Robolectric skips).
- **2c fail-at-stock validation:** with the 2c saturation guard temporarily reverted (immediately restored via `git checkout`; shipped 2c code byte-identical), the suite went to `FAILED 1` with exactly `testIgnoresSafeAreaInfiniteMaxHeightMeasureDoesNotOverflow` throwing `java.lang.IllegalArgumentException` — proving the rebuilt test is a genuine, discriminating regression (green with the guard, red without).
- **Toolchain note:** `swift test` needs Xcode's XCTest, not the Command Line Tools — run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (plus `JAVA_HOME`/`ANDROID_HOME`), or the host `SkipTest` module fails with `no such module 'XCTest'` and no JUNIT line is produced.

### 1.57.0 → 1.58.0 (2026-07-09)

- **Upstream range:** `9f4345c..1901924` (7 upstream commits)
- **Upstream files changed:** `Color.swift`, `ContextMenu.swift`, `List.swift`, `DatePicker.swift`, `Picker.swift`, `EnvironmentValues.swift`, `TextField.swift` — zero overlap with our patched files
- **Conflicts:** none
- **Suite result:** PASS — `JUNIT SUITES 9 TESTS 104 PASSED 102 (98.0%) FAILED 0 SKIPPED 2 TIME 128.56` (matches 1.57.0 baseline: 104 tests, 0 failures, 2 upstream Robolectric skips).

---

## Rebase procedure

Use `scripts/rebase-onto-upstream.sh <new-upstream-tag>` to advance the integration branch. The script fetches the upstream tag, rebases `patches/1.58.0` onto it, runs the dual-side suite, and prints the JUNIT summary. It refuses to exit cleanly on suite failure. Drop fix commits whose upstream PRs have been merged before running the rebase.
