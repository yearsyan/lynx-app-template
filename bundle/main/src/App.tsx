// organizeImports is disabled for this file in biome.json: the scaffolder
// rewrites the workspace scope below (@lynx-template -> @<user scope>), which
// changes the sort order relative to the @lynx-js/* imports.
import {
  readAppLocale,
  readColorScheme,
  readSafeAreaInsets,
  statusBar,
} from '@lynx-template/autolink-device';

import { useCallback, useEffect, useState } from '@lynx-js/react';
import { useInitData } from '@lynx-js/react';

import { router } from '@lynx-template/autolink-navigation';
import { useRouteParams } from '@lynx-template/autolink-navigation/react';

import './App.css';
import './components/native-elements.js';
import { PageFrame } from './components/PageFrame.js';
import { setAppLocale, t } from './i18n.js';
import { PAGES, TABS } from './pages/registry.js';
import type { DemoTabMeta } from './pages/registry.js';

const DARK_TILE_BACKGROUNDS: Record<string, string> = {
  '#e7f6ec': '#143522',
  '#e8f0fe': '#172c4d',
  '#e0f2f1': '#12332f',
  '#fff3e0': '#3b2812',
  '#f3e5f5': '#321c38',
  '#e3f2fd': '#172c4d',
  '#e8f5e9': '#143522',
  '#fff8e1': '#3b2f12',
  '#fce4ec': '#3b1826',
};

function GroupSection(props: {
  tab: DemoTabMeta;
  openKeys: ReadonlySet<string>;
  onToggle: (key: string) => void;
  onOpen: (pageKey: string) => void;
}) {
  const { tab, openKeys, onToggle, onOpen } = props;
  const colorScheme = readColorScheme(useInitData());
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
              <text className="Group__title">{t(category.title)}</text>
              <view
                className="Group__icon"
                style={{
                  backgroundColor:
                    colorScheme === 'dark'
                      ? (DARK_TILE_BACKGROUNDS[category.tileBackground] ??
                        category.tileBackground)
                      : category.tileBackground,
                }}
              >
                <text
                  className="Group__iconGlyph"
                  style={{ color: category.tileColor }}
                >
                  {t(category.glyph)}
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
                    pressed-overlay-color={
                      colorScheme === 'dark'
                        ? 'rgba(255, 255, 255, 0.08)'
                        : 'rgba(0, 0, 0, 0.1)'
                    }
                    accessibility-element
                    accessibility-label={t(item.title)}
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
                      <text className="GroupItem__title">{t(item.title)}</text>
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
  const colorScheme = readColorScheme(useInitData());
  const color = props.active
    ? colorScheme === 'dark'
      ? '#30d178'
      : '#07c160'
    : colorScheme === 'dark'
      ? '#98989d'
      : '#9a9a9a';
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
          {t(tab.headline)}
        </text>
      </view>
      <scroll-view
        className="Home__scroll"
        scroll-orientation="vertical"
        scroll-bar-enable={false}
        bounces={false}
      >
        <view
          className="Home__body"
          style={{ paddingBottom: `${64 + bottomInset + 24}px` }}
        >
          <view className="Hero">
            <view className="Hero__icon">
              <text className="Hero__iconText">{t(tab.glyph)}</text>
            </view>
            <text className="Hero__desc">{t(tab.description)}</text>
          </view>
          <GroupSection
            tab={tab}
            openKeys={openKeys}
            onToggle={toggleCategory}
            onOpen={props.onOpen}
          />
        </view>
      </scroll-view>
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
                {t(item.label)}
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
  const initData = useInitData();
  const colorScheme = readColorScheme(initData);
  const locale = readAppLocale(initData);
  setAppLocale(locale);
  const themeClass = colorScheme === 'dark' ? 'theme-dark' : 'theme-light';
  const params = useRouteParams<{ page?: string }>();
  const pageKey = params.page;
  const page = pageKey === undefined ? undefined : PAGES[pageKey];

  useEffect(() => {
    'background only';
    console.info(
      `Lynx API Showcase · ${SystemInfo.platform} · engine ${SystemInfo.engineVersion}`,
    );
    // Mirror the route's own statusBarStyle (the host applied it before the
    // first frame); an overlay route opened over black snapshot margins uses
    // light-content, so a fixed dark-content here would hide the status bar.
    const routeStyle =
      initData?.route?.presentation === 'overlay'
        ? initData.route.statusBarStyle
        : undefined;
    statusBar
      .setStyle(
        routeStyle ??
          (colorScheme === 'dark' ? 'light-content' : 'dark-content'),
      )
      .catch(() => {});
  }, [
    colorScheme,
    initData?.route?.presentation,
    initData?.route?.statusBarStyle,
  ]);

  const open = useCallback(
    (pageKey: string) => {
      'background only';
      router
        .open({
          bundle: 'main',
          statusBarStyle:
            colorScheme === 'dark' ? 'light-content' : 'dark-content',
          params: { page: pageKey },
        })
        .catch((error: Error) =>
          console.error(`Unable to open demo page: ${error.message}`),
        );
    },
    [colorScheme],
  );

  const close = useCallback(() => {
    'background only';
    router.close().catch(() => {});
  }, []);

  if (page !== undefined) {
    if (initData?.route?.presentation === 'inputDialog') {
      // Each native host gives this route a dedicated transparent overlay. It
      // owns keyboard adaptation, while this bundle only paints the panel.
      return (
        <view className={`AppRoot AppRoot--inputDialog ${themeClass}`}>
          {page.render()}
        </view>
      );
    }
    if (initData?.route?.presentation === 'overlay') {
      // Overlay routes composite over the previous page's snapshot backdrop:
      // no page chrome and a transparent root, so the page draws its own modal
      // layout and lets the backdrop show through where it stays unpainted.
      return (
        <view className={`AppRoot AppRoot--present ${themeClass}`}>
          {page.render()}
        </view>
      );
    }
    return (
      <view className={`AppRoot ${themeClass}`}>
        <PageFrame
          title={t(page.title)}
          onBack={close}
          keyboardAware={page.keyboardAware}
        >
          {page.render()}
        </PageFrame>
      </view>
    );
  }

  return (
    <view className={`AppRoot ${themeClass}`}>
      <Home onOpen={open} />
    </view>
  );
}
