# Minimal Reproduction Examples

Paste each snippet into a SkipUI-backed Android app (e.g. via `skip app create`). All snippets are self-contained with no external dependencies. Each section states honestly what has and has not been observed at runtime; see `EVIDENCE.md` (in `~/Documents/skipui-mre/`) for the full measurement record.

---

## `IgnoresSafeAreaLayout` overflow guard (regression surface — crash never captured)

**Class**: `IgnoresSafeAreaLayout` expands constraints with plain integer arithmetic. If an unbounded constraint (`Constraints.Infinity` = `Int.MAX_VALUE`) reaches this path with a positive safe-area expansion, the addition wraps to a negative value and `Constraints.copy()` throws by precondition:
```
java.lang.IllegalArgumentException: maxWidth must be >= minWidth
```

**Honest status**: this crash has never been captured in any tested environment. The snippet below opens without crashing at stock on API-34/36/37 emulators, on a physical Samsung Galaxy A17 (Android 16), on Firebase Test Lab devices (Galaxy S22, Pixel 10 Pro), and in a production-scale app A/B at skip-ui 1.58.0. At the current Compose BOM the modal measurement path bounds the constraints before the arithmetic (`PresentationRoot` safe-area padding; `TargetViewLayout` finite bounds). The fix is defensive hardening — the overflow class is eliminated by construction — and this snippet is the regression surface that exercises the guarded path.

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
                    .ignoresSafeArea()                         // ← the guarded expansion path
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

---

## `NavigationStack` safe-area double-inset when toolbar is hidden (reproduced on device)

**Bug**: When `.toolbarVisibility(.hidden, for: .navigationBar)` is applied inside a `NavigationStack`, the content receives an extra top padding equal to the system status-bar height. If the parent layout already compensates for the system inset (the host-pays-inset wrapper below is required to reproduce), the gap is double-counted and appears as a blank band below the status bar.

Root cause (`Navigation.swift`, v2 Box layout):
```swift
// Stock — applies safeTopDp even when bar is explicitly hidden:
let topPadding = arguments.ignoresSafeAreaEdges.contains(.top)
    ? max(topBarHeightDp, safeTopDp)   // ← safeTopDp leaks through
    : topBarHeightDp
```

**At stock (9f4345c)**: measured on physical Samsung Galaxy A17 (Android 16, status bar 100 px, density 2.8125 px/dp): content-area top at y=200 — one extra status-bar height (100 px = 35.6 dp) below the status-bar bottom (y=100). **At this branch**: content-area top at y=100, flush below the status bar. Delta: 100 px = 1× status bar.

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
                            Text("Top gap should be ~0 ✓")
                                .foregroundStyle(.white)
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .toolbarVisibility(.hidden, for: .navigationBar)
                }
            }
            .padding(.top, topInset) // host pays the system top inset once — required to expose the double-count
        }
    }
}

#Preview { ReproduceNavigationInsetDouble() }
```

### Symmetric bottom-bar test (guard is symmetric; this variant is not runtime-measured)

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

- Robolectric sets all `WindowInsets.safeDrawing` values to 0, so neither issue is observable in the automated test suite.
- The double-inset reproduction requires a physical Android device (or an emulator reporting nonzero insets) plus the host-pays-inset wrapper shown; it was measured on a Samsung Galaxy A17 (100 px delta).
- The overflow snippet is a regression surface only: the crash has not been reproduced in any environment to date (emulators, physical device, Firebase Test Lab, production-scale A/B all opened the sheet without crashing at stock).
- To test at stock: point `Package.swift` at the fork's path dep, then `git stash` the fix commits in the local skip-ui checkout, rebuild, install, compare.
