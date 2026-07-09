Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: pre-create both `TopAppBar` scroll behaviors at composition scope to ensure `.navigationBarTitleDisplayMode(.inline)` takes effect on non-scrollable roots.

When `.navigationBarTitleDisplayMode(.inline)` is applied to a `NavigationStack` root whose content is a non-scrollable view (e.g., a `VStack` or `ZStack`), the title bar renders in the large style instead of the compact inline style. The cause is that the scroll behavior composable was created with a single ternary expression selecting between `pinnedScrollBehavior()` and `exitUntilCollapsedScrollBehavior()` at composition time. Because each call to these functions creates and remembers an independent `TopAppBarState` slot, switching the selected branch discards the old slot and creates a new one; on non-scrollable roots the preference propagation that sets `isInlineTitleDisplayMode` can arrive after the initial composition, causing the remembered state to be mismatched. Pre-creating both behaviors unconditionally at the same composition scope prevents any slot from being orphaned, so the transition to `TopAppBar` (inline) is immediate regardless of scroll content. Zero iOS/macOS impact — the entire scroll-behavior selection path is guarded by `#if SKIP`.

### Minimal Reproduction

Paste into a SkipUI-backed Android app (e.g. `skip app create`):

```swift
import SwiftUI

struct ReproduceInlineTitleOnVStack: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("This is non-scrollable content")
                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { ReproduceInlineTitleOnVStack() }
```

**At stock**: the title bar renders in the large (expanded) style; the `.inline` modifier has no visible effect when the root is a `VStack`.

**At this branch**: the title bar renders in the compact inline style, consistent with the `.inline` modifier and the behavior when the root is a `ScrollView`.

### Root Cause

`Navigation.swift` creates the scroll behavior in a single ternary that calls `TopAppBarDefaults.pinnedScrollBehavior()` or `TopAppBarDefaults.exitUntilCollapsedScrollBehavior()` based on `isInlineTitleDisplayMode`:

```swift
// Stock — single ternary, only one @Composable slot created per frame:
let initialScrollBehavior = isInlineTitleDisplayMode
    ? TopAppBarDefaults.pinnedScrollBehavior()
    : TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
```

Both `TopAppBarDefaults.pinnedScrollBehavior()` and `TopAppBarDefaults.exitUntilCollapsedScrollBehavior()` call `rememberTopAppBarState()` internally, which allocates a slot in the composition. Because exactly one branch of the ternary runs per frame, only one slot is ever allocated. When `isInlineTitleDisplayMode` changes (the preference propagates from a child view after initial composition), the ternary switches branches, the old slot is abandoned, and the new branch creates a fresh state — leaving the bar in an indeterminate initial state that does not reflect the intended display mode.

### The Fix

Pre-create both behaviors unconditionally at the same composition scope so each maintains its remembered slot independently:

```swift
// Before (stock):
let initialScrollBehavior = isInlineTitleDisplayMode
    ? TopAppBarDefaults.pinnedScrollBehavior()
    : TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

// After:
let pinnedBehavior = TopAppBarDefaults.pinnedScrollBehavior()
let exitBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
let initialScrollBehavior = isInlineTitleDisplayMode ? pinnedBehavior : exitBehavior
```

Both slots are now created on every composition frame; the selection between them is a cheap reference swap. No `@Composable` slot is orphaned when `isInlineTitleDisplayMode` changes, so the transition to `TopAppBar` (inline) happens on the same recomposition frame that delivers the preference.

### Impact

- **Android**: `.navigationBarTitleDisplayMode(.inline)` now correctly renders the compact title bar on non-scrollable roots (`VStack`, `ZStack`, `Color`, etc.), matching the behavior already present when the root is a `ScrollView`.
- **ScrollView roots**: unaffected — the preference arrives before the first rendered frame for scrollable roots and the single-ternary form already worked in that case.
- **Large title (default / `.large`)**: unaffected — `exitBehavior` is selected; behavior is identical to stock.
- **iOS / macOS**: no effect. The `TopAppBar` scroll behavior path is inside `#if SKIP`.

---

Skip Pull Request Checklist:

- [ ] REQUIRED: I have signed the [Contributor Agreement](https://github.com/skiptools/clabot-config)
- [x] REQUIRED: I have tested my change locally with `swift test`
- [x] OPTIONAL: I have tested my change on an Android emulator or device
- [ ] OPTIONAL: I have tested my change on an iOS simulator or device
- [x] REQUIRED: I have checked whether this change requires a corresponding update in the [Skip Fuse UI](https://github.com/skiptools/skip-fuse-ui) repository
- [ ] OPTIONAL: I have added an example of any UI changes to the [Showcase](https://github.com/skiptools/skipapp-showcase) sample app

-----

- [x] AI was used to generate or assist with generating this PR. *Please specify below how you used AI to help you, and what steps you have taken to manually verify the changes*.

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Behavioral verification: the defect was confirmed on Samsung Galaxy A17 (SM-A176U1, Android 16, build BP4A.251205.006); a `NavigationStack` root `VStack` with `.navigationBarTitleDisplayMode(.inline)` rendered the expanded large bar at stock and the compact inline bar after the fix. The full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero new failures vs the base tag.

## Test Coverage

`Tests/SkipUITests/SkipUITests.swift` adds three tests:

1. **`testInlineTitleDisplayOnNonScrollableRoot`** — uses `SKIP INSERT` Kotlin assertions to model the scroll-behavior selection: inline (`isInline = true`) selects `"pinned"`, large (`isLarge = false`) selects `"exitUntilCollapsed"`. Skipped on iOS/macOS (no Kotlin runtime). **Note: this test passes at both stock and fixed branches** because it models the selection logic inline rather than exercising the production `Navigation.kt` path. In Robolectric, `TopAppBar` preference propagation cannot be driven end-to-end via the `render()` helper; the test serves as a documented proof of the selection logic's correctness.

2. **`testNavigationStackVStackInlineTitleRendersWithoutCrash`** — smoke test: `NavigationStack` with a `VStack` root and `.navigationBarTitleDisplayMode(.inline)` renders without crash. Skipped on macOS AppKit (`.navigationBarTitleDisplayMode` is UIKit/SKIP-only).

3. **`testNavigationStackVStackLargeTitleRendersWithoutCrash`** — smoke test: same with `.large` display mode (regression guard for the default path).

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block). The `TopAppBar` scroll-behavior selection affects only the Compose path; the SwiftUI/native-fuse path is unaffected.
