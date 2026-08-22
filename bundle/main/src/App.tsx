// organizeImports is disabled for this file in biome.json: the scaffolder
// rewrites the workspace scope below (@lynx-template -> @<user scope>), which
// changes the sort order relative to the @lynx-js/* imports.
import { readSafeAreaInsets, statusBar } from '@lynx-template/autolink-device';

import { ScrollView } from '@lynx-js/lynx-ui';

import { useCallback, useEffect, useState } from '@lynx-js/react';
import { useInitData } from '@lynx-js/react';

import { router } from '@lynx-template/autolink-navigation';
import { useRouteParams } from '@lynx-template/autolink-navigation/react';

import './App.css';
import './components/native-elements.js';
import { PageFrame } from './components/PageFrame.js';
import { PAGES, TABS } from './pages/registry.js';
import type { DemoTabMeta } from './pages/registry.js';

function GroupSection(props: {
  tab: DemoTabMeta;
  openKeys: ReadonlySet<string>;
  onToggle: (key: string) => void;
  onOpen: (pageKey: string) => void;
}) {
  const { tab, openKeys, onToggle, onOpen } = props;
  return (
    <view className="GroupList">
      {tab.categories.map((category) => {
        const open = openKeys.has(category.key);
        return (
          <view key={category.key} className="Group">
            <view
              className="Group__header"
              bindtap={() => onToggle(category.key)}
            >
              <text className="Group__title">{category.title}</text>
              <view
                className="Group__icon"
                style={{ backgroundColor: category.tileBackground }}
              >
                <text
                  className="Group__iconGlyph"
                  style={{ color: category.tileColor }}
                >
                  {category.glyph}
                </text>
              </view>
            </view>
            {open ? (
              <view className="Group__items">
                {category.items.map((item, index) => (
                  <pressable-view
                    key={item.key}
                    className="GroupItemPressable"
                    active-opacity={1}
                    pressed-overlay-color="rgba(0, 0, 0, 0.1)"
                    accessibility-element
                    accessibility-label={item.title}
                    accessibility-traits="button"
                    bindpress={() => onOpen(item.key)}
                  >
                    <view
                      className={`GroupItem ${
                        index === category.items.length - 1
                          ? 'GroupItem--last'
                          : ''
                      }`}
                    >
                      <text className="GroupItem__title">{item.title}</text>
                      <text className="GroupItem__chevron">›</text>
                    </view>
                  </pressable-view>
                ))}
              </view>
            ) : null}
          </view>
        );
      })}
    </view>
  );
}

function TabIcon(props: { tab: 'api' | 'ui'; active: boolean }) {
  const color = props.active ? '#07c160' : '#9a9a9a';
  if (props.tab === 'api') {
    // Chip glyph: bordered square with a solid core.
    return (
      <view className="TabIconChip" style={{ borderColor: color }}>
        <view
          className="TabIconChip__core"
          style={{ backgroundColor: color }}
        />
      </view>
    );
  }
  // Grid glyph: four rounded squares.
  return (
    <view className="TabIconGrid">
      {[0, 1, 2, 3].map((index) => (
        <view
          key={index}
          className="TabIconGrid__cell"
          style={{ backgroundColor: color }}
        />
      ))}
    </view>
  );
}

function Home(props: { onOpen: (pageKey: string) => void }) {
  const initData = useInitData();
  const insets = readSafeAreaInsets(initData);
  const topInset = insets.top > 0 ? insets.top : 48;
  const bottomInset = insets.bottom > 0 ? insets.bottom : 0;

  const [tabKey, setTabKey] = useState<'api' | 'ui'>('api');
  // Every category starts expanded, so the home list is long enough to
  // exercise scroll-view fling; headers still toggle freely.
  const [openKeys, setOpenKeys] = useState<ReadonlySet<string>>(
    () => new Set(TABS[0].categories.map((category) => category.key)),
  );
  const tab = TABS.find((item) => item.key === tabKey) ?? TABS[0];

  // The lynx-ui bounce wrapper reads an explicit pixel height from
  // `style.height` (it cannot stretch with flex), so size the scroll area to
  // exactly what remains between the nav bar and the tab bar.
  const viewportHeight = SystemInfo.pixelHeight / SystemInfo.pixelRatio;
  const tabBarHeight = 48 + (bottomInset > 0 ? bottomInset : 10);
  const scrollHeight = viewportHeight - topInset - 44 - tabBarHeight;

  const switchTab = useCallback(
    (key: 'api' | 'ui', categories: DemoTabMeta['categories']) => {
      'background only';
      setTabKey(key);
      setOpenKeys(new Set(categories.map((category) => category.key)));
    },
    [],
  );

  const toggleCategory = useCallback((key: string) => {
    'background only';
    setOpenKeys((current) => {
      const next = new Set(current);
      if (current.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  return (
    <view className="Home">
      <view className="NavBar" style={{ paddingTop: `${topInset}px` }}>
        <text className="NavBar__title NavBar__title--home">
          {tab.headline}
        </text>
      </view>
      <ScrollView
        scrollOrientation="vertical"
        className="Home__scroll"
        style={{ width: '100%', height: `${scrollHeight}px` }}
        bounceableOptions={false}
      >
        <view
          className="Home__body"
          style={{ paddingBottom: `${64 + bottomInset + 24}px` }}
        >
          <view className="Hero">
            <view className="Hero__icon">
              <text className="Hero__iconText">{tab.glyph}</text>
            </view>
            <text className="Hero__desc">{tab.description}</text>
          </view>
          <GroupSection
            tab={tab}
            openKeys={openKeys}
            onToggle={toggleCategory}
            onOpen={props.onOpen}
          />
        </view>
      </ScrollView>
      <view
        className="TabBar"
        style={{ paddingBottom: `${bottomInset > 0 ? bottomInset : 10}px` }}
      >
        {TABS.map((item) => {
          const active = item.key === tabKey;
          return (
            <view
              key={item.key}
              className="TabBar__item"
              bindtap={() => switchTab(item.key, item.categories)}
            >
              <TabIcon tab={item.key} active={active} />
              <text
                className={`TabBar__label ${
                  active ? 'TabBar__label--active' : ''
                }`}
              >
                {item.label}
              </text>
            </view>
          );
        })}
      </view>
    </view>
  );
}

export function App() {
  // The same `main` bundle renders both the home showcase (root native page,
  // no route params) and every demo page (pushed native pages opened with
  // `params.page`). System back pops the pushed native page for free.
  const params = useRouteParams<{ page?: string }>();
  const pageKey = params.page;
  const page = pageKey === undefined ? undefined : PAGES[pageKey];

  useEffect(() => {
    'background only';
    console.info(
      `Lynx API Showcase · ${SystemInfo.platform} · engine ${SystemInfo.engineVersion}`,
    );
    statusBar.setStyle('dark-content').catch(() => {});
  }, []);

  const open = useCallback((pageKey: string) => {
    'background only';
    router
      .open({
        bundle: 'main',
        presentation: 'push',
        params: { page: pageKey },
      })
      .catch((error: Error) =>
        console.error(`Unable to open demo page: ${error.message}`),
      );
  }, []);

  const close = useCallback(() => {
    'background only';
    router.close().catch(() => {});
  }, []);

  if (page !== undefined) {
    return (
      <view className="AppRoot">
        <PageFrame title={page.title} onBack={close}>
          {page.render()}
        </PageFrame>
      </view>
    );
  }

  return (
    <view className="AppRoot">
      <Home onOpen={open} />
    </view>
  );
}
