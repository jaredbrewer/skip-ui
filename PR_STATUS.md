# PR Submission Status — shipping set on upstream 1.58.0

After an adversarial review (2026-07-10), the fork's shipping set is **three** fixes, not five. W4 (inline-title) and W5 (button-ripple) were found unnecessary/harmful and have been withdrawn: their fork production changes are reverted, their regression tests deleted, and their `fix/*` branches removed (local + origin). See FORK.md for the divergence ledger and the withdrawal reasons; the PR drafts for W4/W5 are retained but banner-marked WITHDRAWN.

Dual-side suite green after the cuts: `JUNIT SUITES 9 TESTS 97 PASSED 95 FAILED 0 SKIPPED 2` (was 104; −3 W4 tests, −3 W5 tests, −1 net from the 2c test rebuild). Commits authored Jared Brewer with `Co-Authored-By: Claude` trailers; AI disclosure checked in the shipping drafts.

## Shipping set

| # | Branch | Draft | Evidence state |
|---|--------|-------|----------------|
| 2a | fix/hidden-toolbar-safe-area-inset | PR_DRAFT_2a.md | **Pending device test** (another agent owns the device verification of 2a; fate = keep-or-rework). Prior evidence: device MRE (100px, named trigger) + production-app A/B (100px = 1x status bar, stock 1.58.0 broken / fork fixed, same app+device) + FTL cross-device (Galaxy S22 One UI Δ=44px / Pixel 10 Pro AOSP Δ=40px). Production code untouched by this pass. |
| 2c | fix/ignores-safe-area-constraint-overflow | PR_DRAFT_2c.md | **Gold**: deterministic device crash captured at stock (workaround-reverted production app, verbatim trace at the guarded ComposeLayouts line). Production fix device-confirmed and untouched. Regression test **rebuilt** to drive the REAL `IgnoresSafeAreaLayout` measure lambda (synthetic non-zero `SafeArea` + `verticalScroll` infinite maxHeight) instead of reimplementing the saturation arithmetic — see FORK.md and the note below. |
| W3 | fix/pushed-destination-bottom-inset | PR_DRAFT_pushed-destination-bottom-inset.md | **Confirmed at app scale**: production-app A/B — 135px dead band (1x nav bar) at stock, eliminated in the fork arm; trigger named (panel/TabView composition pushes NavigationStack off the nav-bar boundary). Production fix device-confirmed and untouched. Smoke test **rebuilt** to actually push a destination (seeded `NavigationPath`) rather than only rendering a root. |

## Withdrawn (not submitted; fork changes reverted)

| # | Branch (deleted) | Draft | Reason |
|---|------------------|-------|--------|
| W4 | fix/inline-title-nonscrollable-root | PR_DRAFT_inline-title-nonscrollable-root.md (WITHDRAWN banner) | Rationale code-refuted: the app-bar TYPE is selected from `isInlineTitleDisplayMode` independently of the pre-created scroll behaviors, so pre-creating both does NOT enable the first inline transition (already immediate); it only keeps both `TopAppBarState` slots alive → latent stale offsets on mode flip while scrolled. Zero device benefit (weakest of the five; no runtime differential ever captured). |
| W5 | fix/button-ripple-configuration | PR_DRAFT_button-ripple-configuration.md (WITHDRAWN banner) | Redundant + premise factually wrong: on Material3 ≥ 1.3.0 (1.4.0 resolved here), `MaterialTheme` installs the M3 ripple as `LocalIndication`, which already reads `LocalRippleConfiguration` (removes on null, applies color/alpha). Stock `.clickable(onClick:enabled:)` therefore ALREADY honors `.material3Ripple { _ in nil }`. The fix's premise (`LocalIndication` is the M1 ripple reading `LocalRippleTheme`) is wrong for material3 ≥ 1.3.0, and `indication = null` can discard non-ripple custom indications. |

## 2c/W3 test-rebuild note (adversarial-review follow-up)

The prior 2c/W3 tests were hollow: the 2c arithmetic test reimplemented the saturation locally (passed even if production reverted), tested the WIDTH axis while the crash is on maxHEIGHT, and its smoke omitted a presentation root (so `_safeArea` was nil and the guarded block never ran); the W3 "pushed destination" smoke never pushed a destination. Both production fixes are device-confirmed and were left untouched; only the tests were rebuilt:

- **2c** → `testIgnoresSafeAreaInfiniteMaxHeightMeasureDoesNotOverflow` drives the real production measure lambda by injecting a synthetic `SafeArea` (safe bounds inset 100px top and bottom → positive vertical expansion) and hosting the layout in a `verticalScroll` `Column` (which measures its child with `maxHeight == Constraints.Infinity`). If the saturation guard is removed, that lambda computes `Int.MAX_VALUE + 200` → wraps negative → `Constraints.copy(maxHeight:)` throws during measure → the test fails. The width→height axis naming is fixed. A public smoke (`testIgnoresSafeAreaWithinNavigationStackRendersWithoutCrash`) exercises the guarded path through a `NavigationStack`.
- **W3** → `testPushedDestinationRendersWithoutCrash` now seeds the `NavigationStack` with a non-empty `NavigationPath` so a real destination is pushed and the `RenderEntry` bottom-padding path is exercised. Honest limitation: under Robolectric `WindowInsets.safeDrawing` is 0, so the pushed panel's bottom dead band is 0 in both stock and fork — a rendered geometry assertion cannot distinguish them here; the deterministic dead-band evidence remains the on-device production-app A/B (FORK.md / EVIDENCE.md).

## Pending

- **2a device test** by another agent (keep-or-rework); 2a production code untouched by this pass.
- **Re-tag + app repin**: the fork tag stays `1.58.0+fixes.1` for now. A re-tag to `1.58.0+fixes.2` and the app dependency repin are deferred and batched until 2a resolves.
