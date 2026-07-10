# PR Submission Status — five fixes on upstream 1.58.0

All branches rebased onto upstream 1.58.0 (HEAD, zero-conflict), dual-side suite green (104 tests, 0 failures, 2 known upstream Robolectric skips), commits authored Jared Brewer with Co-Authored-By: Claude trailers, AI disclosure checked in every draft. Owner steps remaining: review drafts → sign CLA (skiptools/clabot-config) → say go.

| # | Branch | Draft | Evidence state |
|---|--------|-------|----------------|
| 1 | fix/hidden-toolbar-safe-area-inset | PR_DRAFT_2a.md | **Gold**: device MRE (100px, named trigger) + production-app A/B (100px = 1x status bar, stock 1.58.0 broken / fork fixed, same app+device) |
| 2 | fix/ignores-safe-area-constraint-overflow | PR_DRAFT_2c.md | Production crash trace + arithmetic-proof regression test; honestly framed as defensive hardening (Robolectric cannot produce nonzero insets; app-scale-only trigger stated) |
| 3 | fix/pushed-destination-bottom-inset | PR_DRAFT_pushed-destination-bottom-inset.md | **Gold**: production-app A/B — 135px dead band (exactly 1x nav bar) at stock, eliminated by this patch alone; trigger named (panel/TabView composition pushes NavigationStack off the nav-bar boundary); MRE non-reproduction documented as why minimal apps miss it |
| 4 | fix/inline-title-nonscrollable-root | PR_DRAFT_inline-title-nonscrollable-root.md | **Weakest**: JUnit test + code reasoning; no isolated app-level differential surfaced by the A/B protocol (timing-race trigger; consider bundling with #3 or shipping last) |
| 5 | fix/button-ripple-configuration | PR_DRAFT_button-ripple-configuration.md | Transpiled-path scoping: JUnit regression test + generated Button.kt diff; SkipFuse-native apps structurally cannot exhibit it (CompositionLocals do not cross JNI) — stated in the draft |

Suggested submission order: 1 → 2 → 3/4 together (shared NavigationStack context) → 5. The fork carries all five on `patches/1.58.0` (tag `1.58.0+fixes.1`) regardless of upstream outcomes; FORK.md is the divergence ledger.
