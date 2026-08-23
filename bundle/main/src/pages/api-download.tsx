import { Input } from '@lynx-js/lynx-ui';
import { useCallback, useEffect, useState } from '@lynx-js/react';
import type {
  DownloadManagerCapabilities,
  DownloadState,
  DownloadTask,
} from '@lynx-template/autolink-download-manager';
import { downloadManager } from '@lynx-template/autolink-download-manager';
import { permissions } from '@lynx-template/autolink-permissions';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { t } from '../i18n.js';

const DEFAULT_DOWNLOAD_URL = 'https://proof.ovh.net/files/100Mb.dat';

const STATE_LABELS: Record<DownloadState, string> = {
  queued: '排队中',
  running: '下载中',
  paused: '已暂停',
  completed: '已完成',
  failed: '失败',
  cancelled: '已取消',
};

type DownloadOperation = 'pause' | 'resume' | 'cancel';

function formatBytes(bytes: number): string {
  'background only';
  const units = ['B', 'KB', 'MB', 'GB'] as const;
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const digits = unitIndex === 0 || value >= 100 ? 0 : 1;
  return `${value.toFixed(digits)} ${units[unitIndex]}`;
}

function taskProgress(task: DownloadTask): number {
  'background only';
  if (task.state === 'completed') return 100;
  if (task.totalBytes === null || task.totalBytes === 0) return 0;
  return Math.min(100, (task.bytesDownloaded / task.totalBytes) * 100);
}

function formatProgress(task: DownloadTask): string {
  'background only';
  if (task.totalBytes === null) {
    return `${formatBytes(task.bytesDownloaded)} · 总大小未知`;
  }
  return `${formatBytes(task.bytesDownloaded)} / ${formatBytes(task.totalBytes)} · ${Math.round(taskProgress(task))}%`;
}

function formatCapabilities(capabilities: DownloadManagerCapabilities): string {
  'background only';
  const modes = capabilities.executionModes
    .map((mode) =>
      mode === 'android-foreground-service' ? 'Android 前台服务' : '应用内',
    )
    .join('、');
  return (
    `${capabilities.platform} · ${modes}\n` +
    `断点续传：${capabilities.byteRangeResume ? '支持' : '不支持'} · ` +
    `进程重启恢复：${capabilities.processRestartRecovery ? '支持' : '不支持'}`
  );
}

function DownloadTaskCard(props: {
  task: DownloadTask;
  busy: boolean;
  onOperate: (operation: DownloadOperation, id: string) => void;
  onRemove: (id: string) => void;
}) {
  const { task } = props;
  const active = task.state === 'queued' || task.state === 'running';
  const resumable = task.state === 'paused' || task.state === 'failed';
  const removable =
    task.state === 'completed' ||
    task.state === 'failed' ||
    task.state === 'cancelled';
  const progress = taskProgress(task);
  const executionLabel =
    task.executionMode === 'android-foreground-service'
      ? 'Android 前台服务'
      : '应用内任务';

  return (
    <view className="DownloadTask">
      <view className="DownloadTask__header">
        <text className="DownloadTask__name">{task.fileName}</text>
        <view
          className={`DownloadTask__state DownloadTask__state--${task.state}`}
        >
          <text
            className={`DownloadTask__stateText DownloadTask__stateText--${task.state}`}
          >
            {t(STATE_LABELS[task.state])}
          </text>
        </view>
      </view>
      <text className="DownloadTask__meta">
        {t(executionLabel)} ·{' '}
        {t(task.persistProgress ? '进度落盘' : '仅进程内')} · {task.id}
      </text>
      <view className="DownloadTask__progress">
        <view
          className={`DownloadTask__progressFill DownloadTask__progressFill--${task.state}`}
          style={{ width: `${progress}%` }}
        />
      </view>
      <text className="DownloadTask__bytes">{t(formatProgress(task))}</text>
      {task.error !== null ? (
        <text className="DownloadTask__error">{task.error}</text>
      ) : null}
      {task.fileUri !== null ? (
        <text className="DownloadTask__file">
          {t('文件：{uri}', { uri: task.fileUri })}
        </text>
      ) : null}
      {active ? (
        <view className="RowButtons">
          <DemoButton
            label="暂停"
            disabled={props.busy}
            onTap={() => props.onOperate('pause', task.id)}
          />
          <DemoButton
            label="取消"
            disabled={props.busy}
            onTap={() => props.onOperate('cancel', task.id)}
          />
        </view>
      ) : null}
      {resumable ? (
        <view className="RowButtons">
          <DemoButton
            label="继续"
            primary
            disabled={props.busy}
            onTap={() => props.onOperate('resume', task.id)}
          />
          <DemoButton
            label="删除"
            disabled={props.busy}
            onTap={() => props.onRemove(task.id)}
          />
        </view>
      ) : null}
      {removable && !resumable ? (
        <DemoButton
          label={task.state === 'completed' ? '删除任务和文件' : '删除任务'}
          disabled={props.busy}
          onTap={() => props.onRemove(task.id)}
        />
      ) : null}
    </view>
  );
}

export function DownloadManagerPage() {
  const [url, setUrl] = useState(DEFAULT_DOWNLOAD_URL);
  const [capabilities, setCapabilities] =
    useState<DownloadManagerCapabilities | null>(null);
  const [capabilityResult, setCapabilityResult] = useState<string | null>(null);
  const [tasks, setTasks] = useState<DownloadTask[]>([]);
  const [result, setResult] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [busyTaskID, setBusyTaskID] = useState<string | null>(null);

  const upsertTask = useCallback((task: DownloadTask) => {
    'background only';
    setTasks((current) => {
      const next = current.filter((item) => item.id !== task.id);
      next.push(task);
      next.sort((left, right) => right.createdAt - left.createdAt);
      return next;
    });
  }, []);

  const refreshTasks = useCallback(() => {
    'background only';
    setRefreshing(true);
    downloadManager
      .listTasks()
      .then((items) => {
        items.sort((left, right) => right.createdAt - left.createdAt);
        setTasks(items);
      })
      .catch((error: Error) => setResult(`刷新失败：${error.message}`))
      .finally(() => setRefreshing(false));
  }, []);

  useEffect(() => {
    'background only';
    downloadManager
      .getCapabilities()
      .then((value) => {
        setCapabilities(value);
        setCapabilityResult(formatCapabilities(value));
      })
      .catch((error: Error) =>
        setCapabilityResult(`能力探测失败：${error.message}`),
      );
    refreshTasks();

    const stopProgress = downloadManager.addEventListener(
      'progress',
      ({ task }) => {
        'background only';
        upsertTask(task);
      },
    );
    const stopState = downloadManager.addEventListener('state', ({ task }) => {
      'background only';
      upsertTask(task);
      if (task.state === 'completed') {
        setResult(`下载完成：${task.fileName}`);
      } else if (task.state === 'failed') {
        setResult(`下载失败：${task.error ?? '未知错误'}`);
      }
    });

    return () => {
      'background only';
      stopProgress();
      stopState();
    };
  }, [refreshTasks, upsertTask]);

  const foregroundSupported =
    capabilities?.executionModes.includes('android-foreground-service') ??
    false;

  const startDownload = useCallback(
    (foreground: boolean) => {
      'background only';
      const source = url.trim();
      if (source.length === 0) {
        setResult('请输入 http:// 或 https:// 下载地址');
        return;
      }
      if (foreground && !foregroundSupported) {
        setResult('当前平台不支持 Android 前台下载模式');
        return;
      }

      setStarting(true);
      setResult(
        foreground
          ? '正在申请通知权限并启动 Android 前台任务…'
          : '正在创建下载任务…',
      );
      const permissionResult = foreground
        ? permissions
            .request('notifications')
            .then((state) => state.status)
            .catch(() => 'unknown')
        : Promise.resolve<string | null>(null);

      permissionResult
        .then((notificationStatus) =>
          downloadManager
            .enqueue({
              url: source,
              fileName: `lynx-demo-${Date.now()}.dat`,
              progressIntervalMs: 250,
              persistProgress: true,
              platform: foreground
                ? {
                    android: {
                      foregroundService: {
                        enabled: true,
                        notificationTitle: t('Lynx 下载演示'),
                        notificationText: t('下载将在应用进入后台后继续'),
                      },
                    },
                  }
                : undefined,
            })
            .then((task) => ({ notificationStatus, task })),
        )
        .then(({ notificationStatus, task }) => {
          upsertTask(task);
          const notificationNote =
            notificationStatus === null
              ? ''
              : ` · 通知权限 ${notificationStatus}`;
          setResult(
            foreground
              ? `前台任务已启动${notificationNote}；进度已落盘，可切到后台观察。`
              : `任务已启动且进度已落盘：${task.fileName}`,
          );
        })
        .catch((error: Error) => setResult(`启动失败：${error.message}`))
        .finally(() => setStarting(false));
    },
    [foregroundSupported, upsertTask, url],
  );

  const operate = useCallback(
    (operation: DownloadOperation, id: string) => {
      'background only';
      setBusyTaskID(id);
      const request =
        operation === 'pause'
          ? downloadManager.pause(id)
          : operation === 'resume'
            ? downloadManager.resume(id)
            : downloadManager.cancel(id);
      request
        .then((task) => {
          upsertTask(task);
          setResult(`${STATE_LABELS[task.state]}：${task.fileName}`);
        })
        .catch((error: Error) => setResult(`操作失败：${error.message}`))
        .finally(() =>
          setBusyTaskID((current) => (current === id ? null : current)),
        );
    },
    [upsertTask],
  );

  const remove = useCallback((id: string) => {
    'background only';
    setBusyTaskID(id);
    downloadManager
      .remove(id, { deleteFile: true })
      .then(() => {
        setTasks((current) => current.filter((task) => task.id !== id));
        setResult('任务记录及其缓存文件已删除');
      })
      .catch((error: Error) => setResult(`删除失败：${error.message}`))
      .finally(() =>
        setBusyTaskID((current) => (current === id ? null : current)),
      );
  }, []);

  return (
    <view>
      <ApiName name="downloadManager" />
      <DemoCard
        title="平台能力"
        desc="先由统一接口探测当前宿主执行模式；Android 额外提供 dataSync 前台服务。"
      >
        <ResultLine text={capabilityResult} placeholder="正在探测下载能力…" />
      </DemoCard>
      <DemoCard
        title="创建下载任务"
        desc="演示任务会开启 persistProgress。杀死 App 后再次进入本页，任务将恢复为暂停态，点击“继续”才会重新下载。默认地址是支持 Range 的 100 MB 公共测试文件。"
      >
        <Input
          className="UiInput DownloadDemo__urlInput"
          placeholder="https://example.com/file.zip"
          value={url}
          onInput={setUrl}
        />
        <DemoButton
          label="开始应用内下载"
          primary
          disabled={starting}
          onTap={() => startDownload(false)}
        />
        <DemoButton
          label={
            foregroundSupported
              ? '开始 Android 前台下载'
              : '当前平台无前台下载能力'
          }
          disabled={starting || !foregroundSupported}
          onTap={() => startDownload(true)}
        />
        <ResultLine
          text={result}
          placeholder="启动后可终止 App；重开后刷新列表并手动继续"
        />
      </DemoCard>
      <DemoCard
        title={`任务列表（${tasks.length}）`}
        desc="开启进度落盘的任务会跨进程保留；中断时的 queued/running 状态统一恢复为 paused，不会在初始化时自动联网。"
      >
        <DemoButton
          label={refreshing ? '正在刷新…' : '刷新任务列表'}
          disabled={refreshing}
          onTap={refreshTasks}
        />
        {tasks.length === 0 ? (
          <ResultLine text={null} placeholder="暂无下载任务" />
        ) : (
          tasks.map((task) => (
            <DownloadTaskCard
              key={task.id}
              task={task}
              busy={busyTaskID === task.id}
              onOperate={operate}
              onRemove={remove}
            />
          ))
        )}
      </DemoCard>
    </view>
  );
}
