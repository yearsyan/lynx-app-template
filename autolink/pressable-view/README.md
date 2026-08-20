# autolink/pressable-view

`<pressable-view>` is a native, child-hosting Lynx element with
TouchableOpacity-style feedback. Gesture arbitration and opacity updates stay
on the platform UI thread; the background JavaScript runtime receives only one
`press` event after a tap is accepted.

```tsx
<pressable-view
  active-opacity={1}
  pressed-overlay-color="rgba(0, 0, 0, 0.1)"
  accessibility-element
  accessibility-label="Open banner"
  accessibility-traits="button"
  bindpress={openBanner}
>
  <view className="Banner">...</view>
</pressable-view>
```

## Contract

- `active-opacity?: number` — pressed opacity multiplier, clamped to `[0, 1]`
  (default `0.7`).
- `pressed-overlay-color?: string` — native foreground state-layer color. Use
  a dark translucent color on light surfaces and a light translucent color on
  dark surfaces. Android renders it as a bounded ripple; iOS and HarmonyOS
  render a full-surface highlight.
- `disabled?: boolean` — suppresses feedback, `press`, and accessibility
  activation.
- `bindpress` — emitted exactly once for a completed press.

Android combines ancestor Lynx `scroll-view` / `list` state with native
view-tree scroll activity, so a touch used to stop inertial scrolling cannot
later become a press. iOS relies on `UIScrollView`'s delayed/cancelled content
touches and verifies scroll state again before activation. HarmonyOS renders an
ArkUI `Button` around the Lynx child slots and rejects sequences observed while
the surrounding content is scrolling.

The element is intentionally a single whole-item target. Do not place another
interactive control inside it; use sibling pressables when nested actions are
required.

Choose the overlay independently for each surface: around
`rgba(0, 0, 0, 0.08)` to `0.12` works well on white or bright backgrounds;
dark surfaces generally use a translucent white overlay instead. Set
`active-opacity={1}` when only the state layer should change.
