Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: saturate `Constraints.Infinity` in `IgnoresSafeAreaLayout` to eliminate a latent integer-overflow crash class on Android.

`IgnoresSafeAreaLayout` in `ComposeLayouts.swift` expands the incoming constraints by the safe-area inset using plain integer arithmetic. Compose uses `Constraints.Infinity` (`Int.MAX_VALUE`) as the sentinel for an unbounded dimension; if an unbounded constraint ever reaches this code path while the expansion is positive, the addition wraps to a large negative value, and `constraints.copy()` rejects it with `IllegalArgumentException` — the `androidx.compose.ui.unit.Constraints` API contract requires `maxWidth >= minWidth` / `maxHeight >= minHeight` and throws by precondition on violation.

This PR is defensive hardening, stated plainly: **we have not captured this crash in isolation** (reproduction status below), but the overflow is proven by arithmetic, and the guard eliminates the overflow class by construction. The guard is surgical: if the constraint is already `Constraints.Infinity`, keep it as `Infinity` (unbounded space stays unbounded regardless of expansion); otherwise add the expansion and `coerceAtLeast(0)` defensively. Zero cost on finite constraints, zero iOS/macOS impact — the entire layout path is guarded by `#if SKIP`.

### The overflow class

Stock code in the `IgnoresSafeAreaLayout` measure block:

```swift
let updatedConstraints = constraints.copy(maxWidth: constraints.maxWidth + expansionLeft + expansionRight, maxHeight: constraints.maxHeight + expansionTop + expansionBottom)
```

Three facts combine into a crash class:

1. `Constraints.Infinity == Int.MAX_VALUE == 2_147_483_647` is Compose's documented sentinel for an unbounded dimension, and unbounded/intrinsic measurement passes it as `maxWidth`/`maxHeight`.
2. Kotlin `Int` addition wraps on overflow: `2_147_483_647 + 135` (135 px being, e.g., a navigation-bar inset at 450 dpi) `= -2_147_483_514`.
3. `Constraints` construction/copy validates its bounds by precondition and throws `IllegalArgumentException` ("maxWidth must be >= minWidth") for a negative max — a hard crash in the middle of the measure pass.

Any composition context that routes an unbounded constraint into `IgnoresSafeAreaLayout` with non-zero safe-area expansion crashes at stock. The guard removes the class regardless of which context does so.

### Reproduction status — honest account

We attempted to capture this crash and could not. The snippet below (a sheet whose content uses `.ignoresSafeArea()` inside a `NavigationStack`) opens without crashing at stock on every environment we tested: API-34, API-36, and API-37 emulators; a physical Samsung Galaxy A17 (SM-A176U1, Android 16, One UI 8.5); Firebase Test Lab devices from two vendors (Samsung Galaxy S22, Pixel 10 Pro); and a production-scale app A/B at skip-ui 1.58.0 — zero `IllegalArgumentException`, `FATAL EXCEPTION`, or `SIGSEGV` entries in any captured logcat.

Code analysis explains why: at the current Compose BOM, the modal presentation path bounds the constraints before they reach this arithmetic — `PresentationRoot` applies safe-area padding for regular sheets, and a `.background(...ignoresSafeArea())` node is measured by `TargetViewLayout` at the finite size of its foreground content. So `Constraints.Infinity` does not reach the unguarded addition on the paths we exercised. The guard exists precisely for any BOM upgrade or composition context that changes this: the failure mode is a hard layout crash, and the protection is two saturating comparisons.

Regression surface (exercises the guarded path; does not crash at stock in the environments listed above):

```swift
import SwiftUI

struct ExerciseConstraintsGuard: View {
    @State private var showSheet = false

    var body: some View {
        Button("Open Sheet — exercises the guarded path") {
            showSheet = true
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                Color.blue
                    .ignoresSafeArea()
                    .overlay(alignment: .center) {
                        Text("Sheet opened ✓")
                            .foregroundStyle(.white)
                            .font(.title2)
                    }
            }
        }
    }
}

#Preview { ExerciseConstraintsGuard() }
```

### The Fix

`ComposeLayouts.swift` — `IgnoresSafeAreaLayout` measurement block:

```swift
// Before (stock):
let updatedConstraints = constraints.copy(maxWidth: constraints.maxWidth + expansionLeft + expansionRight, maxHeight: constraints.maxHeight + expansionTop + expansionBottom)

// After:
// SKIP INSERT: val safeMaxW = if (constraints.maxWidth == Constraints.Infinity) Constraints.Infinity else (constraints.maxWidth + expansionLeft + expansionRight).coerceAtLeast(0)
// SKIP INSERT: val safeMaxH = if (constraints.maxHeight == Constraints.Infinity) Constraints.Infinity else (constraints.maxHeight + expansionTop + expansionBottom).coerceAtLeast(0)
let updatedConstraints = constraints.copy(maxWidth: safeMaxW, maxHeight: safeMaxH)
```

`Infinity` propagates as-is; finite values are unchanged except for a defensive clamp to ≥ 0 (covering the edge case where the safe bounds exceed the presentation bounds).

### Impact

- **Android**: eliminates the `Constraints.Infinity + expansion` overflow class for any view calling `.ignoresSafeArea()`. Finite constraints behave identically to stock.
- **iOS / macOS**: no effect. The entire `IgnoresSafeAreaLayout` is inside `#if SKIP`.
- **Behavior with zero safe-area expansion**: unchanged — the guard does not modify the value.
- **Cost**: two integer comparisons per measure pass; no allocation, no behavioral change on any finite path.

---

Skip Pull Request Checklist:

- [ ] REQUIRED: I have signed the [Contributor Agreement](https://github.com/skiptools/clabot-config) <!-- OWNER: sign before submitting, then check -->
- [x] REQUIRED: I have tested my change locally with `swift test`
- [x] OPTIONAL: I have tested my change on an Android emulator or device
- [ ] OPTIONAL: I have tested my change on an iOS simulator or device
- [x] REQUIRED: I have checked whether this change requires a corresponding update in the [Skip Fuse UI](https://github.com/skiptools/skip-fuse-ui) repository
- [ ] OPTIONAL: I have added an example of any UI changes to the [Showcase](https://github.com/skiptools/skipapp-showcase) sample app

-----

- [x] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Verification performed: the full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero new failures vs the base tag (104 tests, 0 failures, 2 pre-existing upstream skips); the generated Kotlin was inspected to confirm the guard transpiled as intended; and the sheet + `.ignoresSafeArea()` surface was exercised with this branch installed on emulators (API 34/36/37) and a physical Samsung Galaxy A17 (Android 16, build BP4A.251205.006) with no crashes and no layout regressions. To state it plainly: we have not observed this crash at runtime; the change is justified by the arithmetic proof and the `Constraints` API contract, not by a captured trace.

**App-level A/B evidence (production SkipFuse app, Samsung Galaxy A17, One UI 8.5):** A full A/B run was conducted using two builds of a production SkipFuse app differing only in the skip-ui pin: stock 1.58.0 (upstream, this guard absent) vs 1.58.0+fixes.1 (this branch). A sheet with the exact structure described here — a `NavigationStack` inside `.sheet()` with `.background(gradient.ignoresSafeArea())` — was opened in both arms. **Neither arm crashed** (no `IllegalArgumentException`, `FATAL EXCEPTION`, or `SIGSEGV` in either logcat buffer, 15,890 and 13,670 lines respectively), and layout was indistinguishable between arms — i.e., the guard is behaviorally inert on the finite-constraint path, as designed. A Firebase Test Lab run of the same two builds on Samsung Galaxy S22 (One UI) and Pixel 10 Pro (AOSP) also completed the sheet surface with 0 crashes in all four runs.

## Test Coverage

`Tests/SkipUITests/LayoutTests.swift` adds three tests:

1. **`testIgnoresSafeAreaExpansionWithInfiniteConstraints`** — arithmetic-proof test via `SKIP INSERT` Kotlin assertions: (a) `Constraints.Infinity + 148` wraps to a negative value, (b) constructing `Constraints` with the wrapped value throws `IllegalArgumentException`, (c) the saturated form preserves `Constraints.Infinity`, (d) `Constraints` built with the saturated value round-trips without throwing. Skipped on iOS/macOS (no Kotlin runtime).

2. **`testIgnoresSafeAreaExpansionDoesNotCrash`** — smoke test: `Color.red.ignoresSafeArea()` in isolation renders without crash (Robolectric context).

3. **`testIgnoresSafeAreaInsideZStackDoesNotCrash`** — smoke test: `.ignoresSafeArea()` nested inside a `ZStack` renders without crash.

**Caveat**: Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the overflow path cannot be triggered via rendering in the automated suite — and, as stated above, no runtime reproduction of the crash exists in our evidence record. The arithmetic-proof test demonstrates the defect class and the guard directly in Kotlin; the guard eliminates the class by construction.

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block).
