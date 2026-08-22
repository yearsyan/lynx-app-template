import type { ReactNode } from '@lynx-js/react';
import { useInitData } from '@lynx-js/react';
import { readSafeAreaInsets } from '@lynx-template/autolink-device';

/** Detail-page scaffold: nav bar with a back chevron plus a scrollable body. */
export function PageFrame(props: {
  title: string;
  onBack: () => void;
  children?: ReactNode;
}) {
  const initData = useInitData();
  const insets = readSafeAreaInsets(initData);
  const topInset = insets.top > 0 ? insets.top : 48;

  return (
    <view className="Page">
      <view className="NavBar" style={{ paddingTop: `${topInset}px` }}>
        <view className="NavBar__back" bindtap={props.onBack}>
          <text className="NavBar__backIcon">‹</text>
        </view>
        <text className="NavBar__title">{props.title}</text>
      </view>
      <scroll-view
        className="Page__scroll"
        scroll-orientation="vertical"
        scroll-bar-enable={false}
      >
        <view
          className="Page__body"
          style={{
            paddingBottom: `${(insets.bottom > 0 ? insets.bottom : 0) + 24}px`,
          }}
        >
          {props.children}
        </view>
      </scroll-view>
    </view>
  );
}
