Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: saturate `Constraints.Infinity` in `IgnoresSafeAreaLayout` to prevent integer overflow crash on Android.

When a `Sheet` measures its intrinsic height, Compose passes `Constraints.Infinity` (`Int.MAX_VALUE`) as `maxHeight`. The `IgnoresSafeAreaLayout` in `ComposeLayouts.swift` adds safe-area expansion via plain integer arithmetic, causing overflow: `Int.MAX_VALUE + 135` wraps to a large negative value, and `constraints.copy(maxHeight = <negative>)` throws `IllegalArgumentException: maxWidth must be >= minWidth`. This crash occurs deterministically on physical devices (100% repro on Samsung Galaxy A17 (SM-A176U1), Android 16) when opening a sheet containing `.ignoresSafeArea()`.

The fix is a surgical guard: if the constraint is already `Constraints.Infinity`, keep it as `Infinity`; otherwise add the expansion and `coerceAtLeast(0)` defensively. Zero iOS/macOS impact—the entire layout path is guarded by `#if SKIP`.

### Minimal Reproduction

Paste into a SkipUI-backed Android app (e.g. `skip app create`):

```swift
import SwiftUI

struct ReproduceConstraintsOverflow: View {
    @State private var showSheet = false

    var body: some View {
        Button("Open Sheet — crashes at stock") {
            showSheet = true
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                Color.blue
                    .ignoresSafeArea()
                    .overlay(alignment: .center) {
                        Text("Fixed: no crash ✓")
                            .foregroundStyle(.white)
                            .font(.title2)
                    }
            }
        }
    }
}

#Preview { ReproduceConstraintsOverflow() }
```

**At stock**: tapping the button crashes immediately with:
```
java.lang.IllegalArgumentException: maxWidth must be >= minWidth
    at androidx.compose.ui.unit.Constraints.copy-NK---4s(Constraints.kt)
```

Reproduced 3× on physical Samsung Galaxy A17 (SM-A176U1) (Android 16, May 2025 patch). Crash is deterministic—every sheet open.

**At this branch**: sheet opens without crashing.

### Root Cause

`IgnoresSafeAreaLayout` in `ComposeLayouts.swift` performs naive integer arithmetic without overflow guards. When `Sheet` intrinsic-height measurement passes `Constraints(maxWidth = Int.MAX_VALUE, maxHeight = Int.MAX_VALUE)`, adding any positive `expansionTop` (e.g., 135 px — the navigation-bar inset on a Samsung Galaxy A17 @450dpi) causes two's-complement wrap:

```
Int.MAX_VALUE + 135 = Int.MIN_VALUE + 147 = -2,147,483,501
```

`constraints.copy(maxHeight = <negative>)` is then rejected by Compose's constraint validation.

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

The guard fires only when constraint is already `Constraints.Infinity`; finite constraints remain unchanged except for defensive `coerceAtLeast(0)`.

### Impact

- **Android**: eliminates crash for any sheet containing a view that calls `.ignoresSafeArea()`. Finite constraints unchanged (saturation fires only at `Constraints.Infinity`).
- **iOS / macOS**: no effect. The entire `IgnoresSafeAreaLayout` is inside `#if SKIP`.
- **Behavior with finite constraints**: unchanged except for defensive clamp.
- **Behavior with zero safe-area expansion**: unchanged—the guard does not modify the value.

---

Skip Pull Request Checklist:

- [x] REQUIRED: I have signed the [Contributor Agreement](https://github.com/skiptools/clabot-config)
- [x] REQUIRED: I have tested my change locally with `swift test`
- [x] OPTIONAL: I have tested my change on an Android emulator or device
- [ ] OPTIONAL: I have tested my change on an iOS simulator or device
- [x] REQUIRED: I have checked whether this change requires a corresponding update in the [Skip Fuse UI](https://github.com/skiptools/skip-fuse-ui) repository
- [ ] OPTIONAL: I have added an example of any UI changes to the [Showcase](https://github.com/skiptools/skipapp-showcase) sample app

-----

- [x] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Manual/behavioral verification: the defect was reproduced on a physical Samsung Galaxy A17 (SM-A176U1, Android 16, build BP4A.251205.006) before the fix and re-tested after (see reproduction section); the full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero new failures vs the base tag; the generated Kotlin was inspected to confirm the change transpiled as intended.

## Test Coverage

`Tests/SkipUITests/LayoutTests.swift` adds three tests:

1. **`testIgnoresSafeAreaExpansionWithInfiniteConstraints`** — uses `SKIP INSERT` Kotlin assertions to prove: (a) stock arithmetic wraps to negative, (b) the wrapped value causes `IllegalArgumentException`, (c) the saturated value equals `Constraints.Infinity`, (d) `Constraints.copy()` with the saturated value does not throw. Skipped on iOS/macOS (no Kotlin runtime).

2. **`testIgnoresSafeAreaExpansionDoesNotCrash`** — smoke test: `Color.red.ignoresSafeArea()` in isolation renders without crash (Robolectric context).

3. **`testIgnoresSafeAreaInsideZStackDoesNotCrash`** — smoke test: `.ignoresSafeArea()` nested inside a `ZStack` renders without crash.

**Caveat**: Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the overflow path is never triggered via rendering in the automated suite. The constraint-validation test proves the fix logic directly in Kotlin; the definitive behavioral evidence is the 3× device repro at stock and absence of crash at this branch.

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block).
