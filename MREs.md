# Minimal Reproduction Examples

Paste each MRE into a SkipUI-backed Android app (e.g. via `skip app create`) to verify the fix. All MREs are self-contained with no external dependencies.

---

## `IgnoresSafeAreaLayout` crash in sheets

**Bug**: Opening a sheet that contains a `NavigationStack` with a background view using `.ignoresSafeArea()` crashes with:
```
java.lang.IllegalArgumentException: maxWidth must be >= minWidth
```
Root cause: the sheet's intrinsic-height measurement passes `Constraints.Infinity` (`Int.MAX_VALUE`) for `maxHeight`; adding the safe-area expansion overflows to a large negative value, causing `Constraints.copy()` to throw.

**At stock (9f4345c)**: crashes immediately when the sheet opens. **At this branch**: sheet opens without crashing.

```swift
import SwiftUI

struct ReproduceConstraintsOverflow: View {
    @State private var showSheet = false

    var body: some View {
        Button("Open Sheet — must not crash") {
            showSheet = true
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                Color.blue
                    .ignoresSafeArea()                         // ← triggers crash at stock
                    .overlay(alignment: .center) {
                        Text("No crash with fix ✓")
                            .foregroundStyle(.white)
                            .font(.title2)
                    }
            }
        }
    }
}

#Preview { ReproduceConstraintsOverflow() }
```

---

## `NavigationStack` safe-area double-inset when toolbar is hidden

**Bug**: When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the content receives an extra top padding equal to the system status-bar height. If the parent layout already compensates for the system inset, the gap is double-counted and appears as a blank band below the status bar.

Root cause (`Navigation.swift`, v2 Box layout):
```swift
// Stock — applies safeTopDp even when bar is explicitly hidden:
let topPadding = arguments.ignoresSafeAreaEdges.contains(.top)
    ? max(topBarHeightDp, safeTopDp)   // ← safeTopDp leaks through
    : topBarHeightDp
```

**At stock (9f4345c)**: extra top gap ≈ status-bar height. **At this branch**: content sits correctly under the status bar.

```swift
import SwiftUI

struct ReproduceNavigationInsetDouble: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.red.ignoresSafeArea(edges: .top)
                VStack {
                    Spacer().frame(height: 60)
                    Text("Top gap should be ~0 ✓")
                        .foregroundStyle(.white)
                        .font(.headline)
                    Spacer()
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

#Preview { ReproduceNavigationInsetDouble() }
```

### Symmetric bottom-bar test

```swift
import SwiftUI

struct ReproduceNavigationBottomInsetDouble: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.green.ignoresSafeArea(edges: .bottom)
                VStack {
                    Spacer()
                    Text("Bottom gap should be ~0 ✓")
                        .foregroundStyle(.white)
                        .font(.headline)
                    Spacer().frame(height: 40)
                }
            }
            .toolbarVisibility(.hidden, for: .bottomBar)
        }
    }
}

#Preview { ReproduceNavigationBottomInsetDouble() }
```

---

## Notes

- These MREs require a physical Android device (or a high-fidelity emulator with `ro.build.characteristics=phone`) to reproduce the bugs. Robolectric sets all `WindowInsets.safeDrawing` values to 0, so the overflow and extra-padding issues are not triggered in the automated test suite.
- To test at stock: point `Package.swift` at the fork's path dep, then `git stash` the fix commits in the local skip-ui checkout, rebuild, install, reproduce.
