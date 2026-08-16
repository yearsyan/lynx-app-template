import { useCallback, useInitData, useState } from '@lynx-js/react';
import {
  ActivityBottomSheet,
  openActivityBottomSheet,
  useActivityBottomSheet,
} from '@lynx-template/activity-sheet';

import './App.css';

const DEFAULT_MAX_DEPTH = 3;

function positiveInteger(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : fallback;
}

export function App() {
  const params = useInitData()?.route?.params;
  const maxDepth = positiveInteger(params?.maxDepth, DEFAULT_MAX_DEPTH);
  const level = Math.min(positiveInteger(params?.level, 1), maxDepth);
  const [error, setError] = useState('');

  const handleSheetError = useCallback((sheetError: Error) => {
    'background only';
    setError(sheetError.message);
  }, []);
  const sheet = useActivityBottomSheet({ onError: handleSheetError });

  const pushLayer = useCallback(() => {
    'background only';
    if (level >= maxDepth) {
      return;
    }
    setError('');
    openActivityBottomSheet({
      bundle: 'predictive-back-sheet',
      statusBarStyle: 'dark-content',
      params: { level: level + 1, maxDepth },
    }).catch((openError: Error) => {
      'background only';
      setError(openError.message);
    });
  }, [level, maxDepth]);

  return (
    <ActivityBottomSheet controller={sheet}>
      <view className="SheetContent">
        <text className="SheetEyebrow">
          TRANSPARENT ACTIVITY · LAYER {level} OF {maxDepth}
        </text>
        <text className="SheetTitle">Predictive bottom sheet</text>
        <text className="SheetMetric">
          {sheet.phase} · {sheet.percentage}% · edge {sheet.edge}
        </text>
        <view className="SheetProgressTrack">
          <view
            className="SheetProgressFill"
            style={{ width: `${sheet.percentage}%` }}
          />
        </view>
        <text className="SheetHint">
          Swipe Back to move this Activity sheet downward. Release to reveal the
          previous native layer.
        </text>
        {error.length > 0 ? <text className="SheetError">{error}</text> : null}
        <view className="SheetActions">
          {level < maxDepth ? (
            <view
              className="SheetAction SheetAction--primary"
              bindtap={pushLayer}
            >
              <text className="SheetActionLabel SheetActionLabel--primary">
                Push Activity {level + 1}
              </text>
            </view>
          ) : (
            <view className="SheetMaxBadge">
              <text className="SheetMaxBadgeLabel">Maximum depth</text>
            </view>
          )}
          <view className="SheetAction" bindtap={sheet.dismiss}>
            <text className="SheetActionLabel">Close top</text>
          </view>
        </view>
      </view>
    </ActivityBottomSheet>
  );
}
