# SkipUI Fork Verification Plan — fixes/1.57.0

**Fork base:** 1.57.0 (9f4345c7)
**Fixes included:** IgnoresSafeAreaLayout overflow crash + NavigationStack safe-area inset guards

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
- Verified suite ledger on this branch: 11 suites, 99 tests, 97 passed, 0 failed, 2 skipped.
