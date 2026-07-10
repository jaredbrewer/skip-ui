Thank you for contributing to the Skip project! Please review the contribution guide at https://skip.dev/docs/contributing/ for advice and guidance on making high-quality PRs.

## Summary

Fix: saturate `Constraints.Infinity` in `IgnoresSafeAreaLayout` to eliminate an integer-overflow crash class on Android.

`IgnoresSafeAreaLayout` in `ComposeLayouts.swift` expands the incoming constraints by the safe-area inset using plain integer arithmetic. Compose uses `Constraints.Infinity` (`Int.MAX_VALUE`) as the sentinel for an unbounded dimension; if an unbounded constraint reaches this code path while the expansion is positive, the addition wraps to a large negative value, and `constraints.copy()` rejects it with `IllegalArgumentException` — the `androidx.compose.ui.unit.Constraints` API contract requires `maxWidth >= minWidth` / `maxHeight >= minHeight` and throws by precondition on violation.

**Reproduction: achieved on device (deterministic).** A production SkipFuse app crashes on the FIRST open of a sheet whose content background uses `.ignoresSafeArea()` inside a `NavigationStack` — at stock 1.57.0, and the guarded code is unchanged between 1.57.0 and 1.58.0 — while the identical app source survives (and renders the intended edge-to-edge background) with only this branch's fix applied. Device-capture trace, condensed to the `skip.ui` frames — interleaved `androidx` frames elided with `...`; the quoted lines are verbatim (Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation):

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

Notably, the app had been carrying a contemporaneous code-comment workaround for this exact defect — `.ignoresSafeArea()` deliberately omitted on that sheet's background because "double-nesting … crashes" Compose's intrinsic measurement. Apps in the wild are already working around this crash; this fix makes the workaround unnecessary (verified: the same view renders its intended edge-to-edge background on the fixed branch). The guard itself is surgical and zero-cost on finite constraints: if the constraint is already `Constraints.Infinity`, keep it as `Infinity` (unbounded space stays unbounded regardless of expansion); otherwise add the expansion and `coerceAtLeast(0)` defensively. Zero iOS/macOS impact — the entire layout path is guarded by `#if SKIP`.

### The trigger chain (three ingredients, all required)

1. **Sheet presentation** — during presentation, `TargetViewLayout`'s intrinsic-height measurement pass delivers `Constraints.Infinity` as the incoming `maxHeight`.
2. **The `NavigationStack` scaffold's own `IgnoresSafeAreaLayout`** — a `NavigationStack` inside the sheet already emits one safe-area expansion node.
3. **A second, nested `IgnoresSafeAreaLayout`** — introduced by `.ignoresSafeArea()` on the content background.

With all three present, the nested node receives `Constraints.Infinity` during the intrinsic pass with a non-zero safe-area expansion; the unguarded addition overflows to negative; `Constraints.copy` throws mid-measure — a hard crash. Remove any one ingredient and the presentation root bounds the constraints before they reach the arithmetic, which is exactly why minimal compositions and worked-around app code open cleanly (see the reproduction record below). The guard removes the class regardless of which composition context routes the unbounded constraint in.

### The overflow class

Stock code in the `IgnoresSafeAreaLayout` measure block:

```swift
let updatedConstraints = constraints.copy(maxWidth: constraints.maxWidth + expansionLeft + expansionRight, maxHeight: constraints.maxHeight + expansionTop + expansionBottom)
```

Three facts combine into a crash class:

1. `Constraints.Infinity == Int.MAX_VALUE == 2_147_483_647` is Compose's documented sentinel for an unbounded dimension, and unbounded/intrinsic measurement passes it as `maxWidth`/`maxHeight`.
2. Kotlin `Int` addition wraps on overflow: `2_147_483_647 + 135` (135 px being, e.g., a navigation-bar inset at 450 dpi) `= -2_147_483_514`.
3. `Constraints` construction/copy validates its bounds by precondition and throws `IllegalArgumentException` ("maxWidth must be >= minWidth") for a negative max — a hard crash in the middle of the measure pass.

### Reproduction record — honest account

**Captured (deterministic device crash):** the production app that motivated this fix carried a code-comment workaround, deliberately omitting `.ignoresSafeArea()` on a sheet's background gradient with a comment explaining that the resulting double-nesting crashes. Reverting that single modifier — restoring `.ignoresSafeArea()` on the background, i.e., restoring trigger ingredient 3 — under stock skip-ui 1.57.0 crashes on the first open of the sheet with the trace above. The identical source built against this branch opens the same sheet cleanly across five open/close cycles plus a rotation pass, and renders the intended edge-to-edge background that the workaround had sacrificed.

**Earlier negatives, explained:** before the workaround was identified as the missing trigger, we attempted to capture this crash and could not — the minimal snippet below opens without crashing at stock on the API-34 emulator and on the physical Samsung Galaxy A17; the production app's equivalent sheet surface also opened cleanly at stock on Firebase Test Lab devices from two vendors (Samsung Galaxy S22 and Pixel 10 Pro); API-36 and API-37 emulator sessions exercising other surfaces of the same MRE app ran crash-free; and the production-scale app A/B at stock 1.58.0 (with the workaround in place) also opened every sheet cleanly with zero `IllegalArgumentException`, `FATAL EXCEPTION`, or `SIGSEGV` entries in any captured logcat. All of those negatives are real, and all are consistent with the capture: in the production app the trigger was worked around at the app level (ingredient 3 absent), and in the minimal composition the presentation root bounds the constraints before they reach the arithmetic — `PresentationRoot` applies safe-area padding for regular sheets, and a `.background(...ignoresSafeArea())` node in a shallow tree is measured by `TargetViewLayout` at the finite size of its foreground content, so `Constraints.Infinity` never reaches the unguarded addition. The minimal snippet below therefore still does not crash at stock; it is a regression surface for the guarded path, not a reproduction. The deterministic reproduction requires the full three-ingredient composition described above.

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

### Affirmative evidence (attach when opening the PR)

The stock crash has no screenshot — the process dies mid-measure during the intrinsic pass, so the `FATAL EXCEPTION` / `IllegalArgumentException` trace quoted in the Summary is the primary artifact. The secondary, affirmative visual is that the identical sheet presentation survives and renders correctly on this branch (drag-drop into the PR form; GitHub hosts it on upload):

| Image (repo-relative) | Fix · arm · device | What it shows |
| --- | --- | --- |
| `evidence/redacted/2c-fork-sheet.png` | 2c · fork · Samsung Galaxy A17 (production A/B) | The Board Setup modal sheet — presented over a `NavigationStack` whose background uses `.ignoresSafeArea()` (trigger ingredient 3 restored) — renders edge-to-edge with full content (FEN field, piece picker, chessboard). Stock skip-ui crashes on this same presentation. A faint app-specific description string above the sheet was redacted. |

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

- **Android**: eliminates the `Constraints.Infinity + expansion` overflow crash for any view calling `.ignoresSafeArea()` under the trigger chain above. Finite constraints behave identically to stock.
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

**AI use & verification:** The diagnosis, fix, tests, and this PR text were developed with substantial AI assistance (Claude). Verification performed: the crash was reproduced at runtime on a physical device (Samsung Galaxy A17 (SM-A176U1), Android 16 (SDK 36), One UI 8.5, build BP4A.251205.006, 3-button navigation) — stock crashes deterministically on first sheet open once the app-level workaround is reverted, and the fixed branch survives the identical source (see the reproduction record above). The full SkipUI test suite was run on both the Swift-native and skipstone-transpiled Kotlin sides with zero new failures vs the base tag (104 tests, 0 failures, 2 known upstream Robolectric skips); the generated Kotlin was inspected to confirm the guard transpiled as intended; and the sheet + `.ignoresSafeArea()` surface was exercised with this branch installed on the API-34 emulator and the physical Samsung Galaxy A17 with no crashes and no layout regressions (API-36/37 emulator sessions with the branch installed exercised other surfaces of the same MRE app, also crash-free).

**App-level A/B evidence (production SkipFuse app, Samsung Galaxy A17, One UI 8.5):** Two A/B passes were run on the same device. (1) *Workaround in place* — two builds of a production SkipFuse app differing only in the skip-ui pin (stock 1.58.0 vs `1.58.0+fixes.1`, this branch) opened a sheet with a `NavigationStack` and a non-`ignoresSafeArea` background: neither arm crashed (no `IllegalArgumentException`, `FATAL EXCEPTION`, or `SIGSEGV` in either logcat buffer, 15,890 and 13,670 lines respectively) and layout was indistinguishable between arms — expected, because the app-level workaround removes trigger ingredient 3, and it confirms the guard is behaviorally inert on the finite-constraint path, as designed. A Firebase Test Lab run of the same two builds on Samsung Galaxy S22 (SC-51C, One UI, API 36) and Pixel 10 Pro (blazer, AOSP, API 36, gesture navigation) also completed the sheet surface with 0 crashes in all four runs — same explanation. (2) *Workaround reverted (the decisive A/B)* — restoring `.ignoresSafeArea()` on the sheet background: stock skip-ui 1.57.0 crashes on the first sheet open with the trace quoted in the Summary; the identical source pinned to this branch survives five open/close cycles plus rotation and renders the intended edge-to-edge background.

## Test Coverage

`Tests/SkipUITests/LayoutTests.swift` adds three tests:

1. **`testIgnoresSafeAreaExpansionWithInfiniteConstraints`** — arithmetic-proof test via `SKIP INSERT` Kotlin assertions: (a) `Constraints.Infinity + 148` wraps to a negative value, (b) constructing `Constraints` with the wrapped value throws `IllegalArgumentException`, (c) the saturated form preserves `Constraints.Infinity`, (d) `Constraints` built with the saturated value round-trips without throwing. Skipped on iOS/macOS (no Kotlin runtime).

2. **`testIgnoresSafeAreaExpansionDoesNotCrash`** — smoke test: `Color.red.ignoresSafeArea()` in isolation renders without crash (Robolectric context).

3. **`testIgnoresSafeAreaInsideZStackDoesNotCrash`** — smoke test: `.ignoresSafeArea()` nested inside a `ZStack` renders without crash.

**Caveat**: Robolectric returns 0 for all `WindowInsets.safeDrawing` values, so the overflow path cannot be triggered via rendering in the automated suite. The behavioral evidence is the deterministic device reproduction documented above; the arithmetic-proof test demonstrates the defect class and the guard directly in Kotlin, and the guard eliminates the class by construction.

## Details

**Skip Fuse UI Update Required**: No corresponding update needed in skip-fuse-ui. This is a pure SkipUI internal layout fix (inside `#if SKIP` block).
