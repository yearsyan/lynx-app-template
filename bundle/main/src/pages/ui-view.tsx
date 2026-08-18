import type { SwiperRef } from '@lynx-js/lynx-ui';

import { Swiper, SwiperItem } from '@lynx-js/lynx-ui';
import { useRef, useState } from '@lynx-js/react';

import { ApiName, DemoButton, DemoCard } from '../components/Demo.js';

const COLORS = ['#07C160', '#576B95', '#FA9D3B', '#E64340'];
const TITLES = ['第一屏', '第二屏', '第三屏', '第四屏'];

export function SwiperPage() {
  const swiperRef = useRef<SwiperRef>(null);
  const [current, setCurrent] = useState(0);
  // `lynx.__globalProps` is not injected by these hosts on the main thread;
  // SystemInfo is available on both threads.
  const containerWidth = SystemInfo.pixelWidth / SystemInfo.pixelRatio - 32;
  const itemWidth = containerWidth - 48;

  return (
    <view>
      <ApiName name="<Swiper />" />
      <DemoCard
        title="轮播"
        desc="主线程驱动的横滑轮播：跟手滑动、惯性吸附，支持程序化切换与指示点。"
      >
        <view className="SwiperBox">
          <Swiper
            ref={swiperRef}
            data={COLORS}
            itemWidth={itemWidth}
            containerWidth={containerWidth}
            duration={300}
            initialIndex={0}
            onChange={setCurrent}
            mode="normal"
            modeConfig={{ align: 'center', spaceBetween: 12 }}
            autoPlay={false}
          >
            {({ index }) => (
              <SwiperItem>
                <view
                  className="SwiperCard"
                  style={{ backgroundColor: COLORS[index] }}
                >
                  <text className="SwiperCard__text">{TITLES[index]}</text>
                </view>
              </SwiperItem>
            )}
          </Swiper>
        </view>
        <view className="SwiperDots">
          {COLORS.map((color, index) => (
            <view
              key={color}
              className={`SwiperDot ${index === current ? 'SwiperDot--active' : ''}`}
            />
          ))}
        </view>
        <view className="RowButtons">
          <DemoButton
            label="上一张"
            onTap={() => swiperRef.current?.swipePrev()}
          />
          <DemoButton
            label="下一张"
            primary
            onTap={() => swiperRef.current?.swipeNext()}
          />
        </view>
      </DemoCard>
    </view>
  );
}
