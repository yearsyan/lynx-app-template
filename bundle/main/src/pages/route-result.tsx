import { useCallback, useInitData, useState } from '@lynx-js/react';

import { readColorScheme } from '@lynx-template/autolink-device';
import { router } from '@lynx-template/autolink-navigation';
import { useRouteParams } from '@lynx-template/autolink-navigation/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

const PICKS = ['青柠绿', '天空蓝', '琥珀橙'];

/**
 * Demonstrates `router.openForResult` / `router.closeWithResult`: the entry
 * page awaits the opened page's close, which resolves with the object passed
 * to closeWithResult — or undefined after a plain close or system Back.
 */
export function RouteResultPage() {
  const params = useRouteParams<{ page?: string; mode?: string }>();
  if (params.mode === 'picker') {
    return <RouteResultPickerPage />;
  }
  return <RouteResultEntryPage />;
}

function RouteResultEntryPage() {
  const colorScheme = readColorScheme(useInitData());
  const [result, setResult] = useState<string | null>(null);

  const openPicker = useCallback(() => {
    setResult('等待选择页关闭…');
    router
      .openForResult<{ picked: string }>({
        bundle: 'main',
        statusBarStyle:
          colorScheme === 'dark' ? 'light-content' : 'dark-content',
        params: { page: 'routeresult', mode: 'picker' },
      })
      .then((value) => {
        setResult(
          value === undefined
            ? '页面已关闭，未携带结果'
            : `页面已关闭，结果: ${JSON.stringify(value)}`,
        );
      })
      .catch((error: Error) => {
        setResult(`打开失败: ${error.message}`);
      });
  }, [colorScheme]);

  return (
    <view>
      <ApiName name="router.openForResult · closeWithResult" />
      <DemoCard
        title="页面结果回传"
        desc="openForResult 的参数与 open 一致，但其 Promise 会等到打开的页面真正关闭才 resolve；对方调用 closeWithResult 则 resolve 为结果对象，直接返回或系统返回手势则 resolve 为 undefined，打开失败会 reject。"
      >
        <DemoButton label="打开选择页等待结果" primary onTap={openPicker} />
        <ResultLine
          text={result}
          placeholder="选择一项、点直接返回或用系统返回手势，观察结果差异"
        />
      </DemoCard>
    </view>
  );
}

function RouteResultPickerPage() {
  const pick = useCallback((picked: string) => {
    router
      .closeWithResult({ picked })
      .catch((error: Error) =>
        console.error(`Unable to close with result: ${error.message}`),
      );
  }, []);

  const closeWithoutResult = useCallback(() => {
    router.close().catch(() => {});
  }, []);

  return (
    <view>
      <ApiName name="router.closeWithResult" />
      <DemoCard
        title="选择页"
        desc="选择任意一项会以 closeWithResult 携带结果关闭本页；“直接返回”与系统返回手势都不携带结果。也可以从这里再打开一层选择页，验证嵌套等待。"
      >
        {PICKS.map((picked) => (
          <DemoButton
            key={picked}
            label={`选择 ${picked}`}
            onTap={() => pick(picked)}
          />
        ))}
        <DemoButton label="直接返回（不携带结果）" onTap={closeWithoutResult} />
      </DemoCard>
    </view>
  );
}
