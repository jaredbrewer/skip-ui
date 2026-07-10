# PR Submission Status — five fixes on upstream 1.58.0

All branches rebased onto upstream 1.58.0 (HEAD, zero-conflict), dual-side suite green (104 tests, 0 failures, 2 known upstream Robolectric skips), commits authored Jared Brewer with Co-Authored-By: Claude trailers, AI disclosure checked in every draft. Owner steps remaining: review drafts → sign CLA (skiptools/clabot-config) → say go.

| # | Branch | Draft | Evidence state |
|---|--------|-------|----------------|
| 1 | fix/hidden-toolbar-safe-area-inset | PR_DRAFT_2a.md | **Gold**: device MRE (100px, named trigger) + production-app A/B (100px = 1x status bar, stock 1.58.0 broken / fork fixed, same app+device) + **FTL cross-device: Galaxy S22 One UI Δ=44px / Pixel 10 Pro AOSP Δ=40px (gesture nav attenuates quantum; direction confirmed on both vendors, 2026-07-10)** |
| 2 | fix/ignores-safe-area-constraint-overflow | PR_DRAFT_2c.md | **Defensive hardening — no captured crash**: no crash trace exists in the evidence record (never reproduced on any emulator, the A17, FTL, or the production A/B at stock 1.58.0); overflow class proven by arithmetic + the Compose `Constraints` precondition, covered by an arithmetic-proof regression test; FTL: 0 crashes on both One UI and AOSP at stock (4/4 pass, sheet surface included) |
| 3 | fix/pushed-destination-bottom-inset | PR_DRAFT_pushed-destination-bottom-inset.md | **Gold**: production-app A/B — 135px dead band (exactly 1x nav bar) at stock, eliminated by this patch alone; trigger named (panel/TabView composition pushes NavigationStack off the nav-bar boundary); MRE non-reproduction documented as why minimal apps miss it + **FTL: Pixel 10 Pro AOSP fork extends content 55px further (gesture nav, less dead band); Galaxy S22 null (driver did not bound this quantity; content terminates before double-inset zone)** |
| 4 | fix/inline-title-nonscrollable-root | PR_DRAFT_inline-title-nonscrollable-root.md | **Weakest**: JUnit test + code reasoning; no isolated app-level differential surfaced by the A/B protocol (timing-race trigger; consider bundling with #3 or shipping last) |
| 5 | fix/button-ripple-configuration | PR_DRAFT_button-ripple-configuration.md | Transpiled-path scoping: JUnit regression test + generated Button.kt diff; SkipFuse-native apps structurally cannot exhibit it (CompositionLocals do not cross JNI) — stated in the draft |

Suggested submission order: 1 → 2 → 3/4 together (shared NavigationStack context) → 5. The fork carries all five on `patches/1.58.0` (tag `1.58.0+fixes.1`) regardless of upstream outcomes; FORK.md is the divergence ledger.
