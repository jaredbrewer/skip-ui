# Remaining Work — SkipUI Android Safe-Area Fixes

These defects were identified during investigation of the safe-area layout issues fixed in this branch. Each is Android/Compose-only and confirmed on a physical device (Android 16). None are addressed by the fixes already merged.

---

## (i) Scaffold bottom inset double-applied on pushed destinations

**File**: `Sources/SkipUI/SkipUI/Containers/Navigation.swift` (Scaffold / bottom padding)

**Symptom**: When a `NavigationStack` pushes a destination, the bottom content area receives an extra gap equal to one navigation-bar height. Measured as ~135 px on a Pixel 6 Pro (Android 16) at 450 dpi.

This is distinct from the hidden-toolbar safe-area guard (which addresses the top-bar path): the bottom gap here is a separate `navigationBars` inset applied once by the Scaffold wrapper and once more by the `NavigationStack`'s own bottom-bar layout path.

**Investigation starting point**: compare `WindowInsets.navigationBars` consumption in the Scaffold wrapper vs. the bottom-bar padding in the `NavigationStack` Column/Box layouts; look for the point where the same inset is added to both the outer scaffold padding and the inner content padding for a pushed destination.

---

## (ii) `.navigationBarTitleDisplayMode(.inline)` ignored on non-scrollable roots

**File**: `Sources/SkipUI/SkipUI/Containers/Navigation.swift` (title display mode path)

**Symptom**: Applying `.navigationBarTitleDisplayMode(.inline)` to a root view that has no `ScrollView` (e.g. a `VStack` or `ZStack`) has no effect — the title renders in the default large style. The modifier is correctly applied when the root is a `ScrollView`.

**Root cause hypothesis**: the title display mode preference is likely consumed by the scroll-view observation path and never reaches the top-bar compositor when no scroll view is present.

**Impact**: apps that use `NavigationStack` with non-scrollable content and want the compact inline title currently have no workaround short of embedding an empty `ScrollView`.

---

## (iii) Container `LocalRippleConfiguration` not reaching `Button` clickable indication

**File**: `Sources/SkipUI/SkipUI/Controls/Button.swift`

**Symptom**: Setting a custom `LocalRippleConfiguration` (or suppressing ripple via a null configuration) on a container view does not propagate to `Button` tap indicators rendered via the Material 3 `.clickable` modifier. The ripple remains the default M3 accent ripple.

**Root cause hypothesis**: the `Button` Compose implementation applies `.clickable` without threading through `LocalRippleConfiguration` from the surrounding composition. In M3, ripple configuration must be set via `CompositionLocalProvider` at or above the `.clickable` call site.

---

_All three defects are Android/Compose-only. No iOS/macOS behavior is involved._

---

## PR draft stubs (TODO)

The three fixes above have been implemented on this branch (`fixes/1.57.0`). PR drafts for each:

- [ ] PR draft for pushed-destination bottom-inset fix → `fix/pushed-destination-bottom-inset`
- [ ] PR draft for `.inline` title on non-scrollable roots → `fix/inline-title-nonscrollable-root`
- [ ] PR draft for `LocalRippleConfiguration` propagation to `Button` → `fix/button-ripple-configuration`
