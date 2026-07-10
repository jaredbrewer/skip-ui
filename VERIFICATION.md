# SkipUI Fork Verification Plan — patches/1.58.0

**Fork base:** 1.58.0 (1901924); the fails-at-stock matrix below was run at the 1.57.0 base (9f4345c7) — the 1.58.0 rebase was zero-conflict with an unchanged suite ledger (see FORK.md rebase log)
**Fixes included:** IgnoresSafeAreaLayout overflow guard + NavigationStack safe-area inset guards + pushed-destination bottom inset + inline title display mode + Button ripple configuration propagation

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
- Verified suite ledger on this branch: 9 suites, 104 tests, 102 passed, 0 failed, 2 skipped (JUNIT SUITES 9 TESTS 104 PASSED 102 FAILED 0 SKIPPED 2 TIME 126.28) — a separate run of the same suite from the FORK.md rebase-log ledger (TIME 128.56); identical composition and counts, wall-clock TIME varies run-to-run.

---

## Fails-at-stock Matrix (Task 1)

Worktrees created at 9f4345c with each branch's test commit cherry-picked alone; `swift test` run to completion. A run counts only if the JUNIT SUITES summary line contains FAILED 0.

### Method

For each of the 5 fix branches the test commit was cherry-picked onto a detached worktree at stock 9f4345c (without the fix commit) and `swift test` run. Each worktree produced a clean JUNIT SUITES … FAILED 0 line. Results below.

### Matrix

| Branch | New test(s) | Native (Swift) | JUnit (Robolectric) | Fails at stock? | Passes on fix branch? |
|---|---|---|---|---|---|
| `fix/ignores-safe-area-constraint-overflow` | `testIgnoresSafeAreaExpansionWithInfiniteConstraints` | SKIPPED (SKIP-only guard) | PASSED | **No** | Yes |
| `fix/hidden-toolbar-safe-area-inset` | `testHiddenToolbarContributesNoSafeAreaPadding` | SKIPPED (SKIP-only guard) | PASSED | **No** | Yes |
| `fix/pushed-destination-bottom-inset` | `testPushedDestinationAppliesBottomInsetOnce` | SKIPPED (SKIP-only guard) | PASSED | **No** | Yes |
| `fix/inline-title-nonscrollable-root` | `testInlineTitleDisplayOnNonScrollableRoot` | SKIPPED (SKIP-only guard) | PASSED | **No** | Yes |
| `fix/button-ripple-configuration` | `testNullRippleConfigurationSuppressesButtonIndication` | SKIPPED (SKIP-only guard) | PASSED | **No** | Yes |

### Why no test fails at stock

All five regression tests use `SKIP INSERT` to model the fix logic directly in Kotlin, rather than calling the production code paths in `Navigation.swift`, `ComposeLayouts.swift`, or `Button.swift`. This means:

1. The test computes the correct result using its own inline guard expression, not by invoking the production Compose layout or composable.
2. Therefore the test passes regardless of whether the fix is present in the production source.
3. Smoke tests (`testIgnoresSafeAreaExpansionDoesNotCrash`, `testPushedDestinationRendersWithoutCrash`, etc.) exercise only the render path; Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the production code path that exhibits the bug is never reached.

### Fix 2c (constraint-overflow) — structural impossibility

For `fix/ignores-safe-area-constraint-overflow`, the task specification calls for strengthening the test until it fails at stock, or documenting why that is structurally impossible. The overflow is structurally impossible to trigger in Robolectric:

- The bug requires `expansionLeft + expansionRight > 0` (i.e., a non-zero safe-area inset).
- Robolectric returns 0 for all `WindowInsets` insets; therefore `expansionLeft = expansionRight = expansionTop = expansionBottom = 0`.
- With expansion = 0: `Constraints.Infinity + 0 = Constraints.Infinity` — no overflow, no crash.
- The only paths to non-zero expansion are (a) running on a real device, or (b) mocking `WindowInsets` at the Robolectric shadow level, which is not supported by the current test infrastructure.
- Even if non-zero insets were injected, calling `IgnoresSafeAreaLayout` from a unit test requires a full Compose measurement context with `Constraints.Infinity` on the outer layout pass — something that occurs in production during `ModalBottomSheet` intrinsic measurement but cannot be replicated via the `render()` helper (which provides bounded constraints).

**Consequence**: `testIgnoresSafeAreaExpansionWithInfiniteConstraints` is an arithmetic-proof test: it demonstrates (via SKIP INSERT) that `Int.MAX_VALUE + 148` wraps to a negative value that `Constraints()` rejects, and that the saturated form preserves `Constraints.Infinity`. The test correctly documents the fix but cannot reproduce the crash in Robolectric; the behavioral reproduction is the 2026-07-10 device capture (workaround-reverted production app at stock 1.57.0 — see EVIDENCE.md). PR_DRAFT_2c.md states both facts: the automated suite cannot trigger the overflow via rendering, and the device capture is the behavioral evidence.

### All other fixes — same structural constraint

For fixes 2a, pushed-destination, inline-title, and button-ripple, the same Robolectric limitation applies: insets are 0, touch interaction is absent, and preference-propagation end-to-end cannot be asserted without a full composition lifecycle. All five regression tests serve as documentation/proof-of-logic tests rather than black-box reproduction tests.

### Definitive evidence per fix

The behavioral evidence differs per fix and is recorded in `/Users/jared/Documents/skipui-mre/evidence/EVIDENCE.md`; the honest per-fix status is:

- **2a (hidden-toolbar inset)**: reproduced and fixed on device. Physical-device MRE on the Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation: 100 px delta = 1× status bar; production-app A/B on the same device: 100 px on the Settings surface (y=345 → y=245); Firebase Test Lab cross-vendor corroboration (Galaxy S22 (SC-51C, One UI, API 36) Δ=44 px, Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) Δ=40 px, same direction).
- **2c (constraint overflow)**: deterministic device crash captured 2026-07-10. The production app carried a contemporaneous workaround (background `.ignoresSafeArea()` deliberately omitted because "double-nesting crashes"); reverting that single modifier under stock skip-ui 1.57.0 (guarded code unchanged through 1.58.0) crashes on first sheet open with the verbatim trace at the guarded ComposeLayouts lines; identical source survives on the fixed branch and renders the intended edge-to-edge background. Earlier all-environments-clean results (the MRE snippet on the API-34 AVD and on the A17; crash-free API-36/37 emulator sessions exercising other surfaces of the same MRE app; FTL production-app sheet runs; the stock-1.58.0 app with workaround) are all explained: the trigger was absent. The minimal MRE snippet still does not crash — it is a regression surface, not a repro.
- **W3 (pushed-destination bottom inset)**: confirmed at app scale only. Production-app A/B on the A17: dead band 310 px → 175 px (Δ=135 px = 1× nav bar); FTL Pixel 10 Pro directional (fork content extends 55 px further; S22 null on this metric this session); the isolated MRE shows zero stock/fork differential on all five tested environments plus two bisect rounds.
- **W4 (inline title)**: the weakest of the five — no runtime stock/fork differential captured anywhere (MRE zero-delta on all environments; no isolated app-level signal). Code inspection + JUnit model test only; timing-race hypothesis (preference arriving after first composition).
- **W5 (ripple configuration)**: code inspection + JUnit model test only; transpiled/SkipLite path only — all recorded environments were SkipFuse-native builds, which are structurally identical in both arms (CompositionLocals do not cross JNI), so the defect was never runtime-observed anywhere.
