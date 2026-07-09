# SkipUI Fork Verification Plan — patches/1.57.0

**Fork base:** 1.57.0 (9f4345c7)
**Fixes included:** IgnoresSafeAreaLayout overflow crash + NavigationStack safe-area inset guards + pushed-destination bottom inset + inline title display mode + Button ripple configuration propagation

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

## Step 3 — Device: IgnoresSafeAreaLayout crash fix

1. Install the debug APK on device.
2. Open a sheet that contains a `NavigationStack` with a background view using `.ignoresSafeArea()` (see MREs.md for a self-contained repro).
3. The sheet must open without crashing (`IllegalArgumentException: maxWidth must be >= minWidth`).

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
- Verified suite ledger on this branch: 9 suites, 104 tests, 102 passed, 0 failed, 2 skipped (JUNIT SUITES 9 TESTS 104 PASSED 102 FAILED 0 SKIPPED 2 TIME 126.28).

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

**Consequence**: `testIgnoresSafeAreaExpansionWithInfiniteConstraints` is an arithmetic-proof test: it demonstrates (via SKIP INSERT) that `Int.MAX_VALUE + 148` wraps to a negative value that `Constraints()` rejects, and that the saturated form preserves `Constraints.Infinity`. The test correctly documents the fix but cannot reproduce the crash. This is stated in PR_DRAFT_2c.md. PR_DRAFT_2c.md is already honest: it says "Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the overflow path is never triggered via rendering" and labels the test as an arithmetic-proof test accordingly.

### All other fixes — same structural constraint

For fixes 2a, pushed-destination, inline-title, and button-ripple, the same Robolectric limitation applies: insets are 0, touch interaction is absent, and preference-propagation end-to-end cannot be asserted without a full composition lifecycle. All five regression tests serve as documentation/proof-of-logic tests rather than black-box reproduction tests. The definitive evidence for each fix is the physical-device run on Samsung Galaxy A17 (SM-A176U1) (Android 16, build BP4A.251205.006), documented in `/Users/jared/Documents/skipui-mre/evidence/EVIDENCE.md`, and the source-code inspection documented in the individual PR drafts.
