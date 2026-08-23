import type { SheetRootRef } from '@lynx-js/lynx-ui';
import {
  DialogBackdrop,
  DialogClose,
  DialogContent,
  DialogRoot,
  DialogTrigger,
  DialogView,
  SheetBackdrop,
  SheetContent,
  SheetHandle,
  SheetRoot,
  SheetView,
} from '@lynx-js/lynx-ui';
import { useRef, useState } from '@lynx-js/react';
import { useBackDismissal } from '@lynx-template/autolink-navigation/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { t } from '../i18n.js';

export function DialogPage() {
  const [show, setShow] = useState(false);
  const [result, setResult] = useState<string | null>(null);

  useBackDismissal(() => setShow(false), show);

  return (
    <view>
      <ApiName name="<DialogRoot />" />
      <DemoCard
        title="对话框"
        desc="模态对话框：Backdrop 遮罩 + Content 内容 + Trigger / Close 触发器，支持受控开关。对话框打开期间系统返回先关闭对话框，而不是退出页面。"
      >
        <DialogRoot
          show={show}
          onShowChange={setShow}
          onOpen={() => setResult('对话框已打开')}
          onClose={() => setResult('对话框已关闭')}
        >
          <DialogTrigger className="DemoButton DemoButton--primary">
            <text className="DemoButton__label DemoButton__label--primary">
              {t('打开对话框')}
            </text>
          </DialogTrigger>
          <DialogView className="UiDialog__viewport">
            <DialogBackdrop className="UiDialog__backdrop" />
            <DialogContent className="UiDialog__content">
              <view className="UiDialog__body">
                <text className="UiDialog__title">{t('删除这条记录？')}</text>
                <text className="UiDialog__desc">
                  {t('删除后无法恢复，请确认该操作是你本人发起。')}
                </text>
              </view>
              <view className="UiDialog__footer">
                <DialogClose className="UiDialog__action">
                  <text className="UiDialog__actionText">{t('取消')}</text>
                </DialogClose>
                <DialogClose className="UiDialog__action UiDialog__action--danger">
                  <view bindtap={() => setResult('已确认删除')}>
                    <text className="UiDialog__actionText UiDialog__actionText--danger">
                      {t('删除')}
                    </text>
                  </view>
                </DialogClose>
              </view>
            </DialogContent>
          </DialogView>
        </DialogRoot>
        <ResultLine text={result} placeholder="点击按钮打开一个模态对话框" />
      </DemoCard>
    </view>
  );
}

const SNAP_POINTS = ['55%'];

export function SheetPage() {
  const sheetRef = useRef<SheetRootRef>(null);
  const [result, setResult] = useState<string | null>(null);

  return (
    <view>
      <ApiName name="<SheetRoot />" />
      <DemoCard
        title="底部弹层"
        desc="从屏幕底部升起的弹层：支持吸附点、拖拽手势与点击遮罩关闭，手势由主线程驱动。"
      >
        <DemoButton
          label="打开底部弹层"
          primary
          onTap={() => sheetRef.current?.open()}
        />
        <SheetRoot
          ref={sheetRef}
          snapPoints={SNAP_POINTS}
          initialSnap={0}
          onOpen={() => setResult('弹层已打开')}
          onClose={() => setResult('弹层已关闭')}
        >
          <SheetView className="UiSheet__viewport">
            <SheetBackdrop className="UiSheet__backdrop" clickToClose={true} />
            <SheetContent
              className="UiSheet__content"
              innerClassName="UiSheet__inner"
            >
              <SheetHandle className="UiSheet__handle" />
              <view className="UiSheet__panel">
                <text className="UiSheet__title">{t('底部弹层')}</text>
                <text className="UiSheet__desc">
                  {t('可以拖动顶部的把手调整高度，或点击遮罩区域关闭。')}
                </text>
                <DemoButton
                  label="关闭弹层"
                  onTap={() => sheetRef.current?.close()}
                />
              </view>
            </SheetContent>
          </SheetView>
        </SheetRoot>
        <ResultLine text={result} placeholder="打开后试试拖拽与遮罩关闭" />
      </DemoCard>
    </view>
  );
}
