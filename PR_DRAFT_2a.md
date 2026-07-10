Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: suppress safe-area inset fallback in `NavigationStack` when toolbar is explicitly hidden.

When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the Compose layout falls back to `WindowInsets.safeDrawing.calculateTopPadding()` as content padding even though the bar height is already zeroed. If the parent layout already compensates for the system inset, the gap is double-counted, appearing as a blank band below the status bar. Device measurement on a Samsung Galaxy A17 (SM-A176U1), Android 16 confirmed a 100 px delta between stock and this branch — exactly one status-bar height (35.6 dp), i.e., the inset applied twice at stock and once with the fix.

The fix adds a surgical guard in four places (v1 Column layout top/bottom, v2 Box layout top/bottom): if `visibility == .hidden`, use 0 dp instead of the safe-area fallback. Automatic-hide (title-less roots where `showTopBar == false` but `visibility != .hidden`) is unaffected. Zero iOS/macOS impact—the entire layout path is guarded by `#if SKIP`.

### Minimal Reproduction

Paste into a SkipUI-backed Android app (e.g. `skip app create`):

```swift
import SwiftUI

struct ReproduceNavigationInsetDouble: View {
    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            VStack(spacing: 0) {
                NavigationStack {
                    ZStack {
                        Color.red.ignoresSafeArea(edges: .top)
                        VStack {
                            Spacer().frame(height: 60)
                            Text("Top gap should be ~0 with fix ✓")
                                .foregroundStyle(.white)
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .toolbarVisibility(.hidden, for: .navigationBar)
                }
            }
            .padding(.top, topInset) // host pays the system top inset once
        }
    }
}

#Preview { ReproduceNavigationInsetDouble() }
```

The host pays the system top inset once (the `GeometryReader` + `.padding(.top, topInset)` pattern used by apps that draw their own chrome). At stock, the hidden-toolbar `NavigationStack` pays it a second time.

**At stock**: a blank band of one status-bar height (100 px = 35.6 dp on the test device) appears between the status bar and the red canvas. Measured via uiautomator on a Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation (status bar 100 px, density 2.8125 px/dp): content-area top at **y=200** — 100 px below the status-bar bottom (y=100).

**At this branch**: the red canvas extends flush below the status bar; content-area top at **y=100**. Delta: **100 px = 1× status-bar height (35.6 dp)** — confirms one inset was being applied twice.

### Affirmative evidence (attach when opening the PR)

Redacted A/B screenshots for this fix (drag-drop into the PR form; GitHub hosts them on upload). App name, developer handle, and copyright were redacted; only generic UI (board-theme / piece-set list, tab bar) remains.

| Image (repo-relative) | Fix · arm · device | What it shows |
| --- | --- | --- |
| `evidence/redacted/app-ab/stock-settings-tab.png` | 2a · stock · Samsung Galaxy A17 (production A/B) | Hidden-toolbar Settings root: ~100 px blank dead band at the top; the first list section ("Board theme") sits well below the status bar. |
| `evidence/redacted/app-ab/fork-settings-tab.png` | 2a · fork · Samsung Galaxy A17 (production A/B) | Same screen on this branch: top inset removed, content shifted up **~100 px (1× status-bar height, 35.6 dp)**; an extra "Board" section is now visible in the same viewport. |
| `evidence/redacted/ftl/stock-sc51c-tab-settings.png` | 2a · stock · Galaxy S22 (SC-51C, Firebase Test Lab) | Cross-device confirmation: top dead band present before the first list section (Δ **44 px** on this device — smaller quantum, same direction). |
| `evidence/redacted/ftl/fork-sc51c-tab-settings.png` | 2a · fork · Galaxy S22 (SC-51C, Firebase Test Lab) | Top inset corrected; list content begins at the nav-bar bottom. |

### Root Cause

`Navigation.swift`, v2 Box layout, applies safe-area inset padding regardless of explicit toolbar visibility:

```swift
// Stock — safeTopDp applied even when bar is hidden:
let topPadding = arguments.ignoresSafeAreaEdges.contains(.top)
    ? max(topBarHeightDp, safeTopDp)   // ← safeTopDp leaks when bar is hidden
    : topBarHeightDp
```

When toolbar is explicitly hidden:
- `topBarHeightDp == 0.dp` (zeroed by `LaunchedEffect` on `showTopBar` change)
- `safeTopDp > 0.dp` on physical device (e.g., 35.6 dp on the Samsung Galaxy A17)
- Result: `topPadding = max(0.dp, safeTopDp) = safeTopDp` applied again on top of parent's system-inset padding

The same defect exists in v1 Column layout and bottom-bar paths of both layouts.

### The Fix

Four surgical guard additions in `Navigation.swift`:

**v1 Column layout — top** (~line 601):

```swift
// Before:
let topPadding = topBarBottomPx.value <= Float(0.0) && arguments.ignoresSafeAreaEdges.contains(.top)
    ? WindowInsets.safeDrawing.asPaddingValues().calculateTopPadding() : 0.dp

// After:
let topPadding = topBarBottomPx.value <= Float(0.0)
    && topBarPreferences?.visibility != .hidden
    && arguments.ignoresSafeAreaEdges.contains(.top)
    ? WindowInsets.safeDrawing.asPaddingValues().calculateTopPadding() : 0.dp
```

**v2 Box layout — top** (~line 681):

```swift
// Before:
let topPadding = arguments.ignoresSafeAreaEdges.contains(.top)
    ? max(topBarHeightDp, safeTopDp) : topBarHeightDp

// After:
let topPadding: Dp
if topBarPreferences?.visibility == .hidden && arguments.ignoresSafeAreaEdges.contains(.top) {
    topPadding = 0.dp
} else if arguments.ignoresSafeAreaEdges.contains(.top) {
    topPadding = max(topBarHeightDp, safeTopDp)
} else {
    topPadding = topBarHeightDp
}
```

Bottom-bar paths are symmetric in both layouts. All four locations change only the `visibility == .hidden` branch; all other code paths are identical to stock.

### Impact

- **Android**: eliminates extra blank band when `.toolbarVisibility(.hidden, for: .navigationBar)` is used inside a `NavigationStack` whose parent consumes the system inset.
- **iOS / macOS**: no effect. The entire Compose layout path is inside `#if SKIP`.
- **Automatic-hide path**: unaffected—guard fires only on explicit `.hidden`.
- **Visible-bar path**: unaffected—guard is gated on `visibility == .hidden`.
- **Behavior with zero inset**: unchanged—`max(0.dp, 0.dp) == 0.dp` in both stock and branch.

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

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Manual/behavioral verification: the defect was reproduced on a physical Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation before the fix and re-tested after (see reproduction section); the full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero new failures vs the base tag (104 tests, 0 failures, 2 known upstream Robolectric skips); the generated Kotlin was inspected to confirm the change transpiled as intended.

**App-level A/B evidence (production SkipFuse app, Samsung Galaxy A17, One UI 8.5):** A full A/B run was conducted using two builds of a production SkipFuse app differing only in the skip-ui pin: stock 1.58.0 (upstream, this fix absent) vs 1.58.0+fixes.1 (this branch). The app uses a hidden-toolbar `NavigationStack` for its Settings tab root (no navigation bar title visible; `toolbarVisibility(.hidden, for: .navigationBar)` applied). Measured via uiautomator: **stock first content element at y=345 (245 px below status-bar bottom); fork first content element at y=245 (145 px below status-bar bottom). Delta: 100 px = 1× status-bar height (35.6 dp)**, confirming the double-inset is eliminated. Screenshots: `evidence/app-ab/stock-settings-tab.png` vs `evidence/app-ab/fork-settings-tab.png`. A second hidden-toolbar surface (Game tab panel, content at y=200 in both arms) showed no differential — that surface's layout architecture does not double-pay the top inset at this app version (y=200 = 100 px below status bar = correct single-inset placement). This A/B is on the same device that showed the MRE 2a measurement (100 px shift at the MRE level); the production-app measurement independently confirms the fix on a real hidden-toolbar `NavigationStack` in a full app context.

## Test Coverage

`Tests/SkipUITests/SkipUITests.swift` adds four tests:

1. **`testHiddenToolbarContributesNoSafeAreaPadding`** — uses `SKIP INSERT` Kotlin assertions with a synthetic `safeTopDp = 56.dp` to prove: (a) stock logic produces `56.dp` when bar is hidden (the double-inset), (b) fix logic produces `0.dp`, (c) bottom-bar guard is symmetric. Skipped on iOS/macOS (no Kotlin runtime).

2. **`testNavigationStackWithHiddenNavBarRendersWithoutCrash`** — smoke test: `NavigationStack` with `.toolbarVisibility(.hidden, for: .navigationBar)` renders without crash. Skipped on macOS AppKit (`.navigationBar` is UIKit-only).

3. **`testNavigationStackWithHiddenBottomBarRendersWithoutCrash`** — same for `.bottomBar`.

4. **`testNavigationStackWithVisibleToolbarRendersWithoutCrash`** — regression guard: visible toolbar still renders (fix must not break the happy path).

**Caveat**: Robolectric sets `WindowInsets.safeDrawing` to 0, so the double-inset is not observable via rendering in the automated suite. The guard-logic test proves correctness with a synthetic value; the definitive behavioral evidence is the device measurement (100 px delta = 1× status-bar height) on the Samsung Galaxy A17 (SM-A176U1), Android 16, corroborated at app scale on the same device (100 px, see the A/B section above) and cross-vendor by a Firebase Test Lab run of the same two app builds (Samsung Galaxy S22 (SC-51C, One UI, API 36) Δ=44 px, Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) Δ=40 px on the same surface — smaller quantum consistent with those devices' smaller transparent/gesture insets, same direction).

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block).
