Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: pass actual expanded edges into `NavigationEntryArguments` to correct pushed-destination bottom inset.

When a `NavigationStack` is embedded inside a panel layout (e.g., a `VStack` containing a custom tab bar below the navigation content), pushed destinations receive an extra dead band at the bottom equal to one navigation-bar height. The `IgnoresSafeAreaLayout` node inside `NavigationStack` correctly determines via adjacency check that the stack is NOT adjacent to the system navigation-bar boundary — yet the initial candidate edge set (`ignoresSafeAreaEdges = [.bottom]`) was passed directly into `NavigationEntryArguments` instead of the adjacency-check result. `RenderEntry`'s bottom-padding guard then applied `navigationBars` inset padding because it saw `.bottom` in the edge set, even though the layout was not actually adjacent to the navigation bar. The fix passes `actualExpandedEdges` (the second closure parameter from `IgnoresSafeAreaLayout`) into `NavigationEntryArguments`, making the bottom-padding guard honor the true adjacency result. Zero iOS/macOS impact — the entire Compose layout path is guarded by `#if SKIP`.

### Minimal Reproduction

Paste into a SkipUI-backed Android app (e.g. `skip app create`):

```swift
import SwiftUI

struct ReproducePushedDestinationInset: View {
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                NavigationLink("Push") {
                    Color.green
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            Text("Dead band below? Stock=YES Fix=NO")
                                .foregroundStyle(.white)
                                .padding(.bottom, 12)
                        }
                        .navigationTitle("Detail")
                }
                .navigationTitle("Root")
            }
            // Simulated custom tab bar forces NavigationStack off the nav-bar boundary:
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 49)
        }
    }
}

#Preview { ReproducePushedDestinationInset() }
```

**Expected mechanism**: at stock, the pushed destination's content area is padded at the bottom by one navigation-bar height (48 dp; 135 px on the Samsung Galaxy A17 test device) even though the stack is not adjacent to the navigation bar; with this branch the padding follows the adjacency result and the dead band is absent.

**Isolated-repro caveat (stated honestly)**: this minimal snippet does not produce a stock/fix differential in our testing — measured identical (zero delta, natural list padding only) on API-34, API-36, and API-37 emulators and on a physical Samsung Galaxy A17 both at its 3-button navigation default and after a navigation-mode switch retry. At this composition depth the adjacency check already returns the correct empty edge set in both builds. The defect surfaces in deeper production composition trees (TabView → VStack → NavigationStack → pushed entry), where the adjacency result and the passed edge set diverge; see the app-level A/B evidence below, where stock shows exactly one navigation-bar height of extra dead band and this branch eliminates it.

### Affirmative evidence (attach when opening the PR)

Redacted cross-device screenshots for this fix (drag-drop into the PR form; GitHub hosts them on upload). The primary confirmed magnitude is the app-ab A/B measurement (stock dead band 310 px → fork 175 px; **Δ = 135 px = 1× navigation-bar height, 48 dp**); the pushed-destination "About" screens below show the same effect visually on two Firebase Test Lab devices. The About header (app name, icon, version, developer credit) and any copyright / repo-URL license lines are redacted; only generic third-party attribution (Stockfish / Lichess / GPL notices) and the section layout remain.

| Image (repo-relative) | Fix · arm · device | What it shows |
| --- | --- | --- |
| `evidence/redacted/ftl/stock-sc51c-pushed-destination.png` | W3 · stock · Galaxy S22 (SC-51C, Firebase Test Lab) | Pushed About destination scrolled to the end: only the "Acknowledgements" section is reachable; the "Licenses" section is pushed off-screen by the bottom dead band. |
| `evidence/redacted/ftl/fork-sc51c-pushed-destination.png` | W3 · fork · Galaxy S22 (SC-51C, Firebase Test Lab) | Same screen on this branch: both "Acknowledgements" and the "Licenses" header are now reachable — dead band reduced, more content visible. Clear delta vs the stock arm. |
| `evidence/redacted/ftl/stock-blazer-pushed-destination.png` | W3 · stock · Pixel 10 Pro (blazer, Firebase Test Lab) | Licenses body cut off after its first line; the bottom dead band prevents scrolling further. |
| `evidence/redacted/ftl/fork-blazer-pushed-destination.png` | W3 · fork · Pixel 10 Pro (blazer, Firebase Test Lab) | Two additional Licenses lines visible — content extends **55 px** further down; dead band reduced (smaller quantum, gesture-nav inset). |

### Root Cause

`Navigation.swift` captures `ignoresSafeAreaEdges` from the surrounding `View` modifier and passes it as both the `expandInto` and `checkEdges` parameters of `IgnoresSafeAreaLayout`, then uses the SAME outer-scope `ignoresSafeAreaEdges` variable inside the layout closure for `NavigationEntryArguments`:

```swift
// Stock — ignoresSafeAreaEdges used inside closure regardless of adjacency result:
IgnoresSafeAreaLayout(expandInto: ignoresSafeAreaEdges, checkEdges: ignoresSafeAreaEdges, logTag: "NavigationStack") { _, _ in
    // ...
    let arguments = NavigationEntryArguments(
        isRoot: true, ..., ignoresSafeAreaEdges: ignoresSafeAreaEdges, ...)
    // ...
    let arguments = NavigationEntryArguments(
        isRoot: false, ..., ignoresSafeAreaEdges: ignoresSafeAreaEdges, ...)
}
```

`IgnoresSafeAreaLayout` calls `adjacentSafeAreaEdges()` each frame and passes the result as the second closure parameter. When the `NavigationStack` is inside a panel layout, `adjacentSafeAreaEdges()` returns `{}` for `.bottom` (not adjacent to `safeBoundsPx.bottom`). But `ignoresSafeAreaEdges` (the outer variable, always `[.bottom]`) is used instead of the closure result, so `RenderEntry` always applies bottom padding.

### The Fix

Bind the second closure parameter (`actualExpandedEdges`) and use it in place of `ignoresSafeAreaEdges` when constructing `NavigationEntryArguments`:

```swift
// Before:
IgnoresSafeAreaLayout(expandInto: ignoresSafeAreaEdges, checkEdges: ignoresSafeAreaEdges, logTag: "NavigationStack") { _, _ in
    let arguments = NavigationEntryArguments(
        isRoot: true, ..., ignoresSafeAreaEdges: ignoresSafeAreaEdges, ...)
    // ...
    let arguments = NavigationEntryArguments(
        isRoot: false, ..., ignoresSafeAreaEdges: ignoresSafeAreaEdges, ...)
}

// After:
IgnoresSafeAreaLayout(expandInto: ignoresSafeAreaEdges, checkEdges: ignoresSafeAreaEdges, logTag: "NavigationStack") { _, actualExpandedEdges in
    let arguments = NavigationEntryArguments(
        isRoot: true, ..., ignoresSafeAreaEdges: actualExpandedEdges, ...)
    // ...
    let arguments = NavigationEntryArguments(
        isRoot: false, ..., ignoresSafeAreaEdges: actualExpandedEdges, ...)
}
```

The change is two substitutions in the closure body. All other logic is unchanged. A standalone full-screen `NavigationStack` IS adjacent to `safeBoundsPx.bottom` on every frame, so `actualExpandedEdges` still contains `.bottom` and the padding is applied correctly; the fix does not regress the full-screen case.

### Impact

- **Android**: eliminates dead band on pushed destinations inside panel layouts (custom tab bars, split-pane, etc.) where `NavigationStack` is not adjacent to the system navigation-bar boundary.
- **Full-screen NavigationStack**: unaffected — adjacency check returns `[.bottom]` and padding is applied as before.
- **Root destinations**: fix applies to both root (`isRoot: true`) and pushed (`isRoot: false`) entries consistently.
- **iOS / macOS**: no effect. The entire Compose layout path is inside `#if SKIP`.
- **Top-edge path**: unaffected — the fix is in the bottom-edge `NavigationEntryArguments` construction only.

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

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Behavioral verification: the defect was confirmed on a Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation, in an app context where a `NavigationStack` was hosted inside a `VStack` alongside a custom tab bar, producing a dead band at the bottom of pushed destinations consistent with one navigation-bar height (Samsung Galaxy A17 navigation bar measures 135 px = 48 dp). The full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero failures (fork shipping suite: 97 tests, 0 failures, 2 known upstream Robolectric skips).

**App-level A/B evidence (production SkipFuse app, Samsung Galaxy A17, One UI 8.5):** A full A/B run was conducted using two builds of a production SkipFuse app differing only in the skip-ui pin: stock 1.58.0 (upstream, this fix absent) vs 1.58.0+fixes.1 (this branch). The app uses a custom tab bar `VStack` layout where the `NavigationStack` is pushed off the navigation-bar boundary — exactly the triggering condition described in this PR. A pushed destination screen was scrolled to maximum extent in both arms and the bottom dead band measured via uiautomator: **stock dead band = 310 px (110 dp); fork dead band = 175 px (62 dp). Delta: 135 px = 1× navigation-bar height (48 dp)**, confirming the extra dead band is eliminated. Breakdown: natural list padding = 175 px; extra dead band at stock = 310−175 = 135 px = one navigation bar. Samsung Galaxy A17 navigation bar = 135 px = 48 dp — exact match. This is a direct runtime differential: broken in stock 1.58.0, fixed in this branch, same app on same device. Affirmative screenshots are the Firebase Test Lab pushed-destination pairs attached in the Affirmative evidence section above (Galaxy S22 and Pixel 10 Pro); the app-ab About-screen capture is intentionally omitted because on that device the stock and fork pushed-destination geometry is identical (the 135 px delta there is the uiautomator measurement quoted above, not a visible band). A Firebase Test Lab run of the same two builds corroborated directionally on a second vendor: on Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) the fixed build's pushed-destination content extends 55 px further down (less dead band; smaller quantum consistent with the smaller gesture-nav inset); the Galaxy S22 (SC-51C, One UI, API 36) run was null for this metric (the screen's content terminated above the affected zone in that session).

**MRE evidence — emulator and physical device:** NOT-REPRODUCED in the standalone MRE app on all five test environments: API-34 AVD (SwiftShader, 3-button nav), API-36 AVD (SwiftShader, 3-button nav), API-37 AVD (SwiftShader, 16KB page-size image), Samsung Galaxy A17 at its 3-button navigation default (navigation_mode=0), and Samsung Galaxy A17 after a navigation-mode switch retry (navigation_mode=2). On the Samsung Galaxy A17 specifically: stock APK dead band = 34 px, fork APK dead band = 34 px — zero differential with either nav mode. Two additional device-side bisect rounds that added candidate trigger ingredients to the MRE composition (outer `.ignoresSafeArea()` edge combinations) also produced zero stock/fork differential. The MRE's simpler `VStack { NavigationStack + Rectangle }` composition does not expose the full-app triggering condition (the adjacency-check result returns `{}` for `.bottom` in both stock and fork at this composition depth, so no stock/fork differential is produced in isolation). The production app's multi-layer composition tree (TabView → VStack → NavigationStack → pushed entry) is required to expose the adjacency-check differential.

## Test Coverage

`Tests/SkipUITests/SkipUITests.swift` adds two tests:

1. **`testPushedDestinationAppliesBottomInsetOnce`** — uses `SKIP INSERT` Kotlin assertions to model the adjacency-check guard: (a) panel case — `actualExpandedEdges = {}`, so `panelPadding = 0f` (no dead band); (b) full-screen case — `actualExpandedEdges = {.bottom}`, so `fullPadding = navBarHeight` (correct). Skipped on iOS/macOS (no Kotlin runtime). **Note: this test passes at both stock and fixed branches** because it models the guard logic inline rather than exercising the production `Navigation.kt` path. In Robolectric, `WindowInsets.safeDrawing` returns 0, so the adjacency check cannot be driven to produce the failure condition via rendering. The test serves as a documented proof of the guard's correctness.

2. **`testPushedDestinationRendersWithoutCrash`** — a genuine push smoke: it seeds the `NavigationStack` with a non-empty `NavigationPath` (via `.constant`) plus a `navigationDestination(for:)`, so a real destination is pushed and composed on first render, exercising the `RenderEntry` pushed-destination bottom-padding path this fix corrects. Honest limitation: under Robolectric `WindowInsets.safeDrawing` is 0, so the pushed panel's bottom dead band is 0 in both stock and fork — a rendered geometry assertion cannot distinguish them here; the deterministic dead-band evidence is the on-device production-app A/B above.

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block). The `NavigationEntryArguments` change affects only the Compose measurement path; the SwiftUI/native-fuse path is unaffected.
