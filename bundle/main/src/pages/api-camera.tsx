import { useCallback, useState } from '@lynx-js/react';

import type {
  CameraFlashMode,
  CameraLens,
  CameraPhoto,
  CameraPreviewFit,
  CameraViewCaptureEvent,
  CameraViewErrorEvent,
  CameraViewReadyDetail,
  CameraViewReadyEvent,
  CameraViewStateEvent,
} from '@lynx-template/autolink-camera';
import { camera, cameraView } from '@lynx-template/autolink-camera';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { t } from '../i18n.js';

const CAMERA_SELECTOR = '#camera-demo-preview';

const DEFAULT_CAPABILITIES: CameraViewReadyDetail = {
  lens: 'back',
  zoom: 1,
  minZoom: 1,
  maxZoom: 1,
  torchSupported: false,
  exposureMin: 0,
  exposureMax: 0,
};

function photoSummary(prefix: string, photo: CameraPhoto): string {
  'background only';
  return `${prefix}：${photo.width}×${photo.height} · ${Math.round(
    photo.sizeBytes / 1024,
  )} KB`;
}

/** System camera and native inline-preview demo. */
export function CameraPage() {
  const [active, setActive] = useState(true);
  const [lens, setLens] = useState<CameraLens>('back');
  const [zoom, setZoom] = useState(1);
  const [torch, setTorch] = useState(false);
  const [flash, setFlash] = useState<CameraFlashMode>('auto');
  const [exposure, setExposure] = useState(0);
  const [quality, setQuality] = useState(92);
  const [fit, setFit] = useState<CameraPreviewFit>('cover');
  const [mirrorPhoto, setMirrorPhoto] = useState(true);
  const [capabilities, setCapabilities] =
    useState<CameraViewReadyDetail>(DEFAULT_CAPABILITIES);
  const [state, setState] = useState('stopped');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [lastPhoto, setLastPhoto] = useState<CameraPhoto | null>(null);

  const onReady = useCallback((event: CameraViewReadyEvent) => {
    'background only';
    setCapabilities(event.detail);
    setZoom(event.detail.zoom);
    setResult(
      `相机已就绪：缩放 ${event.detail.minZoom.toFixed(1)}–${event.detail.maxZoom.toFixed(1)}×，曝光 ${event.detail.exposureMin.toFixed(1)}–${event.detail.exposureMax.toFixed(1)} EV`,
    );
  }, []);

  const onStateChange = useCallback((event: CameraViewStateEvent) => {
    'background only';
    setState(event.detail.state);
  }, []);

  const onError = useCallback((event: CameraViewErrorEvent) => {
    'background only';
    setResult(`${event.detail.code}：${event.detail.message}`);
  }, []);

  const onCapture = useCallback((event: CameraViewCaptureEvent) => {
    'background only';
    setLastPhoto(event.detail.photo);
    setResult(photoSummary('内嵌相机拍摄成功', event.detail.photo));
  }, []);

  const takeSystemPhoto = useCallback(() => {
    'background only';
    if (busy) {
      return;
    }
    setBusy(true);
    // Release the inline session before presenting the operating system's
    // camera UI so both do not compete for the same camera device.
    setActive(false);
    setResult('正在打开系统相机…');
    camera
      .takePhoto({ lens })
      .then((outcome) => {
        if (outcome.photo !== null) {
          setLastPhoto(outcome.photo);
          setResult(photoSummary('系统相机拍摄成功', outcome.photo));
        } else {
          setResult(`${outcome.code}：${outcome.message}`);
        }
      })
      .catch((error: Error) => setResult(error.message))
      .finally(() => {
        setBusy(false);
        setActive(true);
      });
  }, [busy, lens]);

  const captureInline = useCallback(() => {
    'background only';
    if (busy) {
      return;
    }
    setBusy(true);
    cameraView
      .capture(CAMERA_SELECTOR)
      .then((photo) => {
        setLastPhoto(photo);
        setResult(photoSummary('内嵌相机拍摄成功', photo));
      })
      .catch((error: Error) => setResult(error.message))
      .finally(() => setBusy(false));
  }, [busy]);

  const focusCenter = useCallback(() => {
    'background only';
    cameraView
      .focusAtPoint(CAMERA_SELECTOR, 0.5, 0.5)
      .then(() => setResult('已在画面中心对焦和测光'))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const changeZoom = useCallback(
    (delta: number) => {
      'background only';
      setZoom((current) =>
        Math.max(
          capabilities.minZoom,
          Math.min(capabilities.maxZoom, current + delta),
        ),
      );
    },
    [capabilities.maxZoom, capabilities.minZoom],
  );

  const changeExposure = useCallback(
    (delta: number) => {
      'background only';
      setExposure((current) =>
        Math.max(
          capabilities.exposureMin,
          Math.min(capabilities.exposureMax, current + delta),
        ),
      );
    },
    [capabilities.exposureMax, capabilities.exposureMin],
  );

  const cycleFlash = useCallback(() => {
    'background only';
    setFlash((current) =>
      current === 'auto' ? 'on' : current === 'on' ? 'off' : 'auto',
    );
  }, []);

  return (
    <view>
      <ApiName name="camera.takePhoto" />
      <DemoCard
        title="系统相机"
        desc="打开系统提供的拍照界面，用户确认后返回应用缓存中的 JPEG。系统相机只接收前/后镜头偏好，具体交互由系统决定。"
      >
        <DemoButton
          label={`使用${lens === 'back' ? '后置' : '前置'}系统相机拍照`}
          primary
          disabled={busy}
          onTap={takeSystemPhoto}
        />
      </DemoCard>

      <ApiName name="<x-camera-view>" />
      <DemoCard
        title="内嵌原生相机"
        desc="首次显示会自动申请权限。预览默认按 cover 居中裁掉长边，保持比例且填满区域；contain 可查看完整画面。"
      >
        <view
          style={{
            width: '100%',
            height: '280px',
            borderRadius: '16px',
            overflow: 'hidden',
            backgroundColor: '#000000',
          }}
        >
          <x-camera-view
            id="camera-demo-preview"
            style={{ width: '100%', height: '100%' }}
            active={active}
            lens={lens}
            zoom={zoom}
            torch={torch ? 'on' : 'off'}
            flash={flash}
            exposure-compensation={exposure}
            photo-quality={quality}
            mirror-photo={mirrorPhoto}
            preview-fit={fit}
            bindready={onReady}
            bindstatechange={onStateChange}
            binderror={onError}
            bindcapture={onCapture}
          />
        </view>

        <text style={{ marginTop: '12px', color: '#57606a', fontSize: '13px' }}>
          {t(
            `状态 ${state} · ${lens === 'back' ? '后置' : '前置'} · ${zoom.toFixed(1)}× · ${exposure.toFixed(1)} EV · JPEG ${quality}%`,
          )}
        </text>
        <DemoButton
          label={active ? '暂停预览' : '启动预览'}
          onTap={() => setActive((current) => !current)}
        />
        <DemoButton
          label={`切换到${lens === 'back' ? '前置' : '后置'}镜头`}
          onTap={() =>
            setLens((current) => (current === 'back' ? 'front' : 'back'))
          }
        />
        <DemoButton
          label={`补光灯：${torch ? '开' : '关'}`}
          disabled={!capabilities.torchSupported}
          onTap={() => setTorch((current) => !current)}
        />
        <DemoButton label={`拍照闪光灯：${flash}`} onTap={cycleFlash} />
        <DemoButton
          label={`预览填充：${fit}`}
          onTap={() =>
            setFit((current) => (current === 'cover' ? 'contain' : 'cover'))
          }
        />
        <DemoButton
          label={`前置成片镜像：${mirrorPhoto ? '开' : '关'}`}
          onTap={() => setMirrorPhoto((current) => !current)}
        />
        <DemoButton
          label={`缩小（当前 ${zoom.toFixed(1)}×）`}
          onTap={() => changeZoom(-0.5)}
        />
        <DemoButton
          label={`放大（最大 ${capabilities.maxZoom.toFixed(1)}×）`}
          onTap={() => changeZoom(0.5)}
        />
        <DemoButton
          label={`降低曝光（当前 ${exposure.toFixed(1)} EV）`}
          onTap={() => changeExposure(-0.5)}
        />
        <DemoButton label="提高曝光" onTap={() => changeExposure(0.5)} />
        <DemoButton
          label={`JPEG 质量：${quality}%`}
          onTap={() =>
            setQuality((current) => (current >= 100 ? 60 : current + 10))
          }
        />
        <DemoButton label="中心对焦 / 测光" onTap={focusCenter} />
        <DemoButton
          label="拍摄当前画面"
          primary
          disabled={busy || state !== 'ready'}
          onTap={captureInline}
        />
        <ResultLine text={result} placeholder="相机状态与拍摄结果显示在这里" />
        {lastPhoto !== null ? (
          <view style={{ marginTop: '12px' }}>
            <image
              src={lastPhoto.uri}
              mode="aspectFill"
              style={{
                width: '100%',
                height: '180px',
                borderRadius: '12px',
              }}
            />
          </view>
        ) : null}
      </DemoCard>
    </view>
  );
}
