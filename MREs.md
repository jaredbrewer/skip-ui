# Minimal Reproduction Examples

Paste each snippet into a SkipUI-backed Android app (e.g. via `skip app create`). All snippets are self-contained with no external dependencies. Each section states honestly what has and has not been observed at runtime; see `EVIDENCE.md` (in `~/Documents/skipui-mre/evidence/`) for the full measurement record.

---

## `IgnoresSafeAreaLayout` overflow guard (crash captured on device 2026-07-10; this snippet is a regression surface and does NOT crash)

**Class**: `IgnoresSafeAreaLayout` expands constraints with plain integer arithmetic. If an unbounded constraint (`Constraints.Infinity` = `Int.MAX_VALUE`) reaches this path with a positive safe-area expansion, the addition wraps to a negative value and `Constraints.copy()` throws by precondition. Device-capture trace, condensed to the `skip.ui` frames — interleaved `androidx` frames elided with `...`; the quoted lines are verbatim (Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation):
```
FATAL EXCEPTION: main
java.lang.IllegalArgumentException: maxWidth must be >= than minWidth,
maxHeight must be >= than minHeight, minWidth and minHeight must be >= 0
  ...
  at skip.ui.ComposeLayoutsKt$IgnoresSafeAreaLayout$6$2.measure-3p2s80s(ComposeLayouts.kt:239)
  ...
  at skip.ui.ComposeLayoutsKt$IgnoresSafeAreaLayout$6$2.maxIntrinsicHeight(ComposeLayouts.kt:235)
  ...
  at skip.ui.ComposeLayoutsKt$TargetViewLayout$1$1$1.measure-3p2s80s(ComposeLayouts.kt:128)
  ...
```

**Honest status**: the crash IS captured — deterministically, on device (2026-07-10). A production SkipFuse app carried a contemporaneous workaround (background `.ignoresSafeArea()` deliberately omitted with a comment that "double-nesting crashes"); reverting that single modifier under stock skip-ui 1.57.0 (the guarded code is unchanged between 1.57.0 and 1.58.0) crashes on the first sheet open, and identical source survives on the fixed branch. The trigger requires three ingredients at once: (1) sheet presentation, whose `TargetViewLayout` intrinsic-height pass delivers `Constraints.Infinity`; (2) the `NavigationStack` scaffold's own `IgnoresSafeAreaLayout`; (3) a second nested `IgnoresSafeAreaLayout` from `.ignoresSafeArea()` on the content background. The minimal snippet below does NOT crash at stock — it opened cleanly on the API-34 emulator and on the physical Samsung Galaxy A17; the production app's equivalent sheet surface also opened cleanly on Firebase Test Lab devices (Galaxy S22, Pixel 10 Pro) and in the production-scale app A/B at skip-ui 1.58.0 with the workaround in place, and API-36/37 emulator sessions exercising other surfaces of the same MRE app ran crash-free — because in a shallow composition the presentation root bounds the constraints before the arithmetic (`PresentationRoot` safe-area padding; `TargetViewLayout` finite bounds). This snippet is the regression surface that exercises the guarded path; the reproduction lives in the workaround-reverted app A/B (see `EVIDENCE.md`).

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

**At stock (9f4345c)**: measured on a physical Samsung Galaxy A17 (SM-A176U1), Android 16 (status bar 100 px, density 2.8125 px/dp): content-area top at y=200 — one extra status-bar height (100 px = 35.6 dp) below the status-bar bottom (y=100). **At this branch**: content-area top at y=100, flush below the status bar. Delta: 100 px = 1× status bar.

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
- The overflow snippet is a regression surface only: it does not crash at stock in any tested environment (the snippet itself on the API-34 emulator and the physical Samsung Galaxy A17; the production app's sheet surface on Firebase Test Lab and in the production-scale A/B with the app-level workaround in place — all opened cleanly). The crash itself was captured on device on 2026-07-10 via the workaround-reverted production app — the minimal snippet lacks the composition depth for the three-ingredient trigger; see `EVIDENCE.md`.
- To test at stock: point `Package.swift` at the fork's path dep, then `git stash` the fix commits in the local skip-ui checkout, rebuild, install, compare.
