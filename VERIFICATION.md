# SkipUI Fork Verification Plan — patches/1.58.0

**Fork base:** 1.58.0 (1901924)
**Shipping fixes (post-adversarial-review, 2026-07-10):** IgnoresSafeAreaLayout overflow guard (2c) + NavigationStack hidden-toolbar safe-area inset guard (2a) + pushed-destination bottom inset (W3). W4 (inline title) and W5 (Button ripple) were **withdrawn** — production reverted, tests deleted, branches removed (see FORK.md).

---

## Step 1 — Clean rebuild via skipstone

```bash
# Wipe cached transpile output so skipstone picks up the fork's Swift sources
rm -rf .build/plugins/outputs/skip-ui
# Re-run skipstone (the skip plugin prebuild step)
swift package plugin --allow-writing-to-package-directory skipstone 2>&1 | grep -E "(error|warning|SkipUI)"
```

Expected: no Swift compile errors from `ComposeLayouts.swift` or `Navigation.swift`. The generated `Navigation.kt` and `ComposeLayouts.kt` should reflect the new code:

```bash
grep -n "safeMaxW" .build/plugins/outputs/skip-ui/SkipUI/destination/skipstone/SkipUI/src/main/kotlin/skip/ui/ComposeLayouts.kt
grep -n "topBarPreferences.*visibility" .build/plugins/outputs/skip-ui/SkipUI/destination/skipstone/SkipUI/src/main/kotlin/skip/ui/Navigation.kt
```

---

## Step 2 — Gradle assemble

```bash
cd Android
./gradlew assembleDebug 2>&1 | tail -40
```

Expected: `BUILD SUCCESSFUL`. Any Kotlin type errors = `SKIP INSERT` syntax issue in the source.

---

## Step 3 — Device: IgnoresSafeAreaLayout overflow guard (regression check)

1. Install the debug APK on device.
2. Open a sheet that contains a `NavigationStack` with a background view using `.ignoresSafeArea()` (see MREs.md for a self-contained surface).
3. The sheet must open without crashing and with layout identical to stock. Note: the overflow crash was captured as a deterministic device crash on 2026-07-10 (production app with its app-level workaround reverted: stock 1.57.0 crashes on first sheet open, the fixed branch survives identical source — see EVIDENCE.md). The minimal MREs.md surface does NOT crash even at stock (the trigger requires the full three-ingredient composition: sheet intrinsic pass + the NavigationStack scaffold's own IgnoresSafeAreaLayout + a nested IgnoresSafeAreaLayout on the content background), so this step verifies the guard introduces no regression and that the fork sources were picked up; the demonstrated crash fix is verified via the workaround-reverted A/B.

---

## Step 4 — Device: NavigationStack safe-area inset guard

Apply the MRE from MREs.md (`.toolbarVisibility(.hidden, for: .navigationBar)` inside a `NavigationStack`). Observe that the red canvas extends flush to the status bar with no extra gap.

Expected: gap ≈ 0. If a gap remains, verify that skipstone picked up the fork sources (Step 1).

### Interpreting results

| Observation | Meaning |
|---|---|
| Gap ~0 on root and pushed | Fix working correctly |
| Gap persists | skipstone did not pick up the fork sources; re-run Step 1 |
| Crash on sheet open | ComposeLayouts fix not transpiled; check safeMaxW grep from Step 1 |

---

## Step 5 — Full automated suite

```bash
source /path/to/env.sh
swift test
```

Expected: 0 failures; 2 upstream skips (Android-only tests on macOS). The regression tests added in this branch should be green.

---

## Notes

- Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the overflow and double-inset are not observable via rendering in the automated suite.
- Test-environment requirement: the transpiled Kotlin/JUnit side requires JDK 17+ (set `JAVA_HOME` accordingly). With the wrong JVM the Kotlin side silently does not execute — always verify the "JUNIT SUITES ... FAILED 0" summary line.
- Verified suite ledger on this branch (post-cut): 9 suites, 97 tests, 95 passed, 0 failed, 2 skipped (JUNIT SUITES 9 TESTS 97 PASSED 95 FAILED 0 SKIPPED 2 TIME 131.36) — was 104 before the W4/W5 withdrawal (−6 tests) and the 2c test rebuild (−1 net).
- Toolchain: `swift test` requires Xcode's XCTest (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); the Command Line Tools alone give `no such module 'XCTest'` and produce no JUNIT line.

---

## Fails-at-stock status (updated 2026-07-10 after the test rebuild)

The earlier version of this matrix claimed all five regression tests were arithmetic-only and none failed at stock — that was the hollowness the adversarial review flagged. The 2c and W3 tests have since been rebuilt; W4/W5 were withdrawn. Current status of the three shipping fixes:

| Fix | Regression test | Native (Swift) | JUnit (Robolectric) | Fails at stock? |
|---|---|---|---|---|
| 2c (`fix/ignores-safe-area-constraint-overflow`) | `testIgnoresSafeAreaInfiniteMaxHeightMeasureDoesNotOverflow` | SKIPPED (SKIP-only) | PASSED on fork | **Yes — verified in-harness** |
| 2a (`fix/hidden-toolbar-safe-area-inset`) | `testHiddenToolbarContributesNoSafeAreaPadding` (untouched) | SKIPPED (SKIP-only) | PASSED | **No** (Robolectric zero-insets; SKIP INSERT model test) |
| W3 (`fix/pushed-destination-bottom-inset`) | `testPushedDestinationRendersWithoutCrash` (rebuilt to actually push) + `testPushedDestinationAppliesBottomInsetOnce` (model) | SKIPPED/rendered | PASSED | **No** (Robolectric zero-insets; genuine push, but dead band is 0 in both arms here) |

### 2c — the rebuilt test genuinely fails at stock

`testIgnoresSafeAreaInfiniteMaxHeightMeasureDoesNotOverflow` drives the REAL `IgnoresSafeAreaLayout` measure lambda. Robolectric's real `WindowInsets.safeDrawing` is 0, which is why a plain render cannot reproduce the overflow — so the test bypasses that limitation two ways: (1) it injects a synthetic `SafeArea` (safe bounds inset 100px top and bottom → positive vertical expansion) via `EnvironmentValues.shared.set_safeArea`; (2) it hosts the layout in a `verticalScroll` `Column`, which measures its child with `maxHeight == Constraints.Infinity` — the same unbounded intrinsic pass the sheet delivers on device. The crash axis is maxHEIGHT (the old test wrongly exercised width).

**Validated:** with the 2c saturation guard temporarily reverted (then restored via `git checkout` — shipped code byte-identical), the suite went from `FAILED 0` to `FAILED 1`, with exactly this test throwing `java.lang.IllegalArgumentException` at the guarded `Constraints.copy(maxHeight:)`. The test passes with the guard and fails without it: a genuine, discriminating regression, not a reimplementation.

### 2a / W3 — honest Robolectric limitation

For 2a and W3 the Robolectric limitation still applies: real `WindowInsets` are 0, so the double-inset (2a) and the pushed-destination dead band (W3) are 0 in both stock and fork under the harness — a rendered geometry assertion cannot distinguish them. `testPushedDestinationRendersWithoutCrash` now at least drives a REAL pushed destination (seeded `NavigationPath`) so the `RenderEntry` bottom-padding path executes, rather than only rendering a root. The deterministic behavioral evidence for both remains the on-device production-app A/B recorded in `EVIDENCE.md`. These are honestly documented as smoke/path tests, not black-box reproductions.

### Definitive evidence per fix

The behavioral evidence differs per fix and is recorded in `/Users/jared/Documents/skipui-mre/evidence/EVIDENCE.md`; the honest per-fix status is:

- **2a (hidden-toolbar inset)**: reproduced and fixed on device. Physical-device MRE on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation: 100 px delta = 1× status bar; production-app A/B on the same device: 100 px on the Settings surface (y=345 → y=245); Firebase Test Lab cross-vendor corroboration (Galaxy S22 (SC-51C, One UI, API 36) Δ=44 px, Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) Δ=40 px, same direction).
- **2c (constraint overflow)**: deterministic device crash captured 2026-07-10. The production app carried a contemporaneous workaround (background `.ignoresSafeArea()` deliberately omitted because "double-nesting crashes"); reverting that single modifier under stock skip-ui 1.57.0 (guarded code unchanged through 1.58.0) crashes on first sheet open with the verbatim trace at the guarded ComposeLayouts lines; identical source survives on the fixed branch and renders the intended edge-to-edge background. Earlier all-environments-clean results (the MRE snippet on the API-34 AVD and on the A17; crash-free API-36/37 emulator sessions exercising other surfaces of the same MRE app; FTL production-app sheet runs; the stock-1.58.0 app with workaround) are all explained: the trigger was absent. The minimal MRE snippet still does not crash — it is a regression surface, not a repro.
- **W3 (pushed-destination bottom inset)**: confirmed at app scale only. Production-app A/B on the A17: dead band 310 px → 175 px (Δ=135 px = 1× nav bar); FTL Pixel 10 Pro directional (fork content extends 55 px further; S22 null on this metric this session); the isolated MRE shows zero stock/fork differential on all five tested environments plus two bisect rounds.
- **W4 (inline title) and W5 (ripple configuration)**: WITHDRAWN 2026-07-10 — production reverted, tests deleted, branches removed. W4's rationale was code-refuted (app-bar type is selected independently of the pre-created behaviors; the only effect was keeping both `TopAppBarState` slots alive — a latent stale-offset risk). W5 was redundant + premise-wrong (on Material3 ≥ 1.3.0, `MaterialTheme` installs the M3 ripple as `LocalIndication`, which already honors `LocalRippleConfiguration`, so stock already suppresses/customises the ripple). See FORK.md.
