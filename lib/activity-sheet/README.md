# Activity Bottom Sheet

ReactLynx component infrastructure for a full-width bottom sheet hosted by a
transparent native route. It owns the visual shell, native safe-area padding,
predictive-back lifecycle, cancel rebound, and route dismissal timing.

```tsx
import {
  ActivityBottomSheet,
  openActivityBottomSheet,
  useActivityBottomSheet,
} from '@lynx-template/activity-sheet';

function openFilters() {
  'background only';
  return openActivityBottomSheet({
    bundle: 'filters',
    params: { source: 'home' },
  });
}

function FiltersSheet() {
  const sheet = useActivityBottomSheet();

  return (
    <ActivityBottomSheet controller={sheet}>
      <text>Filters</text>
      <view bindtap={sheet.dismiss}>
        <text>Close</text>
      </view>
    </ActivityBottomSheet>
  );
}
```

`openActivityBottomSheet()` always uses `presentation: 'sheet'` and
`transparent: true`. The destination bundle must render
`ActivityBottomSheet`, otherwise the native window will be transparent but no
sheet UI will be visible.
