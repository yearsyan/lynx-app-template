import { useCallback, useState } from '@lynx-js/react';

import { openActivityBottomSheet } from '@lynx-template/activity-sheet';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

const MAX_DEMO_LAYERS = 3;

export function ActivitySheetPage() {
  const [result, setResult] = useState<string | null>(null);

  const open = useCallback(() => {
    'background only';
    setResult('正在打开透明 Activity 底部弹层…');
    openActivityBottomSheet({
      bundle: 'predictive-back-sheet',
      statusBarStyle: 'dark-content',
      params: { level: 1, maxDepth: MAX_DEMO_LAYERS },
    })
      .then(() => setResult('弹层已打开，可继续下推 3 层，返回仅收回顶层'))
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="openActivityBottomSheet" />
      <DemoCard
        title="半透明堆叠页"
        desc="在透明 Activity 中以全宽底部弹层打开另一个 Lynx bundle，最多下推 3 层原生页面；返回手势只让顶层页面下沉，呈现逐层堆叠效果。"
      >
        <DemoButton label="打开堆叠演示" primary onTap={open} />
        <ResultLine text={result} placeholder="体验原生级的页面堆叠与返回" />
      </DemoCard>
    </view>
  );
}
