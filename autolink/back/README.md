# @lynx-template/autolink-back

Package-owned system Back interception and predictive overlay rendering for
Lynx hosts. The package owns its NativeModule, `<predictive-back-overlay>`
Element, LIFO dispatcher, event validation, and React APIs on all three
platforms.

For a fixed popup, menu, dialog, or sheet, prefer the high-level API:

```tsx
import {
  PredictiveBackOverlay,
  usePredictiveBackOverlay,
} from '@lynx-template/autolink-back/react';

function ExampleSheet() {
  const sheet = usePredictiveBackOverlay();
  return (
    <view>
      <view bindtap={sheet.present}>Open</view>
      <PredictiveBackOverlay
        open={sheet.open}
        onOpenChange={sheet.setOpen}
        backdropColor="rgba(0, 0, 0, 0.45)"
        motion="sheet"
      >
        <view className="Sheet">Content</view>
      </PredictiveBackOverlay>
    </view>
  );
}
```

Android and iOS pin the top interceptor and its native Element when a gesture
starts, then update that Element directly on the UI thread. There is no
per-frame NativeModule → background JavaScript → render-thread round trip.
The backdrop opacity and the `sheet` / `horizontal` / `none` motion preset are
therefore native-grade animation targets, while React receives only lifecycle
events needed to settle state. HarmonyOS exposes no public Back progress API,
so the same component closes on its discrete `start` → `commit` pair.

For route handling or another headless use case, import `backStack` from the
package root or `useBackInterceptor` from the `/react` entry. A headless
interceptor deliberately has no animation target: if it is above an overlay,
the lower overlay will not move. Every gesture remains pinned to the entry
that received `start`, even if the stack changes before `cancel` or `commit`.

- Android uses the hosting `FragmentActivity` and AndroidX
  `OnBackPressedDispatcher`. Android 14+ provides predictive progress; older
  releases produce a discrete commit.
- iOS discovers the owning `UIViewController`, coordinates the navigation
  controller gesture/button, and drives a leading-edge interactive preview.
- HarmonyOS keeps the package-owned route controller and declarative
  `onBackPress` adapter; it does not invent synthetic progress.

Native interception is enabled only while the stack is non-empty. Do not mix
the raw `back.setEnabled()` lifecycle with `backStack` on the same LynxView.
