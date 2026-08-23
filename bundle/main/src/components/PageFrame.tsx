import { KeyboardAwareResponder, KeyboardAwareRoot } from '@lynx-js/lynx-ui';
import type { ReactNode } from '@lynx-js/react';
import { useInitData } from '@lynx-js/react';
import {
  readNavigationBarInsetBottom,
  readSafeAreaInsets,
} from '@lynx-template/autolink-device';

import { t } from '../i18n.js';

export interface PageFrameProps {
  title: string;
  onBack: () => void;
  /**
   * Enables keyboard-aware scrolling for this page. Wrap each focus target in
   * `KeyboardAwareTrigger` so the responder can keep it above the keyboard.
   */
  keyboardAware?: boolean;
  children?: ReactNode;
}

/** Detail-page scaffold: nav bar with a back chevron plus a scrollable body. */
export function PageFrame(props: PageFrameProps) {
  const initData = useInitData();
  const insets = readSafeAreaInsets(initData);
  const topInset = insets.top > 0 ? insets.top : 48;
  const bottomInset = insets.bottom > 0 ? insets.bottom : 0;
  const navigationBarInsetBottom = readNavigationBarInsetBottom(initData);

  const body = (
    <view
      className="Page__body"
      style={{ paddingBottom: `${bottomInset + 24}px` }}
    >
      {props.children}
    </view>
  );

  return (
    <view className="Page">
      <view className="NavBar" style={{ paddingTop: `${topInset}px` }}>
        <view className="NavBar__back" bindtap={props.onBack}>
          <text className="NavBar__backIcon">‹</text>
        </view>
        <text className="NavBar__title">{t(props.title)}</text>
      </view>
      {props.keyboardAware ? (
        <view className="Page__viewport">
          <KeyboardAwareRoot
            androidStatusBarPlusBottomBarHeight={navigationBarInsetBottom}
          >
            <KeyboardAwareResponder
              as="ScrollView"
              className="Page__scroll"
              style={{ width: '100%', height: '100%' }}
              scrollviewId="page-frame-keyboard-scroll"
              bounceableOptions={false}
            >
              {body}
            </KeyboardAwareResponder>
          </KeyboardAwareRoot>
        </view>
      ) : (
        <scroll-view
          className="Page__scroll"
          scroll-orientation="vertical"
          scroll-bar-enable={false}
          bounces={false}
        >
          {body}
        </scroll-view>
      )}
    </view>
  );
}
