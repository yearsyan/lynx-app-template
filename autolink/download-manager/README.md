# Download manager autolink

`@lynx-template/autolink-download-manager` exposes one task API across Android,
iOS, and HarmonyOS. Platform-specific execution is negotiated through
`getCapabilities()` and requested through `platform` options, so callers do not
need separate download state machines.

## Usage

```ts
import { downloadManager } from '@lynx-template/autolink-download-manager';

const capabilities = await downloadManager.getCapabilities();

const stopProgress = downloadManager.addEventListener('progress', ({ task }) => {
  'background only';
  console.info(`${task.id}: ${task.bytesDownloaded}/${task.totalBytes ?? '?'}`);
});

const stopState = downloadManager.addEventListener('state', ({ task }) => {
  'background only';
  console.info(`${task.id}: ${task.state}`);
});

const task = await downloadManager.enqueue({
  url: 'https://example.com/archive.zip',
  fileName: 'archive.zip',
  headers: { 'X-Archive-Variant': 'full' },
  persistProgress: true,
  platform: {
    android: capabilities.executionModes.includes(
      'android-foreground-service',
    )
      ? {
          foregroundService: {
            enabled: true,
            notificationTitle: 'Downloading archive',
            notificationText: 'The download continues in the background',
          },
        }
      : undefined,
  },
});

await downloadManager.pause(task.id);
await downloadManager.resume(task.id);

stopProgress();
stopState();
```

The public methods are:

- `getCapabilities()`
- `enqueue(options)`
- `pause(id)`, `resume(id)`, and `cancel(id)`
- `getTask(id)` and `listTasks()`
- `remove(id, { deleteFile })`
- `addEventListener('progress' | 'state', listener)`

A task moves through `queued`, `running`, `paused`, `completed`, `failed`, or
`cancelled`. Completed tasks expose a local `file://` URI. Downloads are stored
under an app-private cache directory, so the operating system may evict them;
move long-lived files into permanent app storage before relying on them.

## Persisted tasks and manual recovery

Set `persistProgress: true` when creating a task to persist its request
configuration, state, progress, range validator, and partial file. The default
is `false`, preserving the process-memory-only behavior for callers that do not
opt in.

On the next DownloadManager initialization after process termination or device
restart, persisted tasks are available from `getTask()` and `listTasks()`.
Interrupted `queued` or `running` tasks are always restored as `paused`. The
manager never starts network activity while loading records; the application
must explicitly call `resume(task.id)` after a user or product decision. Failed
and manually paused tasks also remain resumable, while terminal records remain
listed until `remove()` is called.

Metadata is stored in the app-private durable files/Application Support area.
Partial and completed payloads remain in the app cache, and their actual file
length is treated as the source of truth when a record is restored. Cache
eviction can therefore reset a partial download to zero or turn a completed
record into `failed` with a missing-file error.

Persisted request headers are written to app-private metadata as plain text,
without application-level encryption. Avoid storing long-lived bearer tokens
in a persisted task; prefer short-lived credentials or an application-specific
credential refresh strategy. Use HTTPS in production. Android and HarmonyOS
cleartext HTTP are Debug-only under the template host policy.

## Platform execution

| Platform | Execution modes | Resume behavior | Host background behavior |
| --- | --- | --- | --- |
| Android | `in-app`, `android-foreground-service` | Resumes a `.part` file with HTTP Range and `If-Range` when supported upstream | The optional `dataSync` foreground service keeps an enabled transfer running after the app UI enters the background |
| iOS | `in-app` | Persisted tasks use a `.part` file with HTTP Range; non-persisted tasks use `NSURLSession` resume data when available | No background-session entitlement; an interrupted process restores work as paused on the next launch |
| HarmonyOS | `in-app` | Resumes a `.part` file with HTTP Range and `If-Range` when supported upstream | No background task agent yet; an interrupted process restores work as paused on the next launch |

On Android, the library manifest contributes `INTERNET`, foreground-service,
`dataSync`, and notification declarations automatically. Start a foreground
download while the app is eligible to launch a foreground service. On Android
13 and newer, the host should request `POST_NOTIFICATIONS` at runtime so users
can see the normal notification. If Android stops a long-running `dataSync`
service because of a system time limit, active foreground tasks are paused and
emit a state event instead of silently continuing without the service.

All three hosts report `processRestartRecovery: true`. This capability means
that opt-in records can be restored; it never means they auto-resume. Android
foreground execution also does not change the restart rule: if the process is
terminated, the restored task waits in `paused` until `resume()` is called.

HarmonyOS consumers must declare `ohos.permission.INTERNET` in the entry
module. The template host already includes it.

## Architecture

The raw NativeModule contract lives in
`types/platform-native-module.d.ts`; generated bridge bindings live in `src/`,
and the handwritten facade validates all input and native payloads. Android uses
a process-wide engine so replacing a Lynx page does not cancel transfers. iOS
uses a shared `NSURLSession` store, and HarmonyOS uses a process-wide streaming
store. Each host keeps persisted metadata outside the payload cache and loads
it before serving task queries. All implementations emit the same
`downloadManager` global event payload.

Future platform executors should add an execution-mode capability and consume
a platform option while preserving the common task/event contract. This keeps
capability selection at the boundary rather than spreading platform checks
through application code.
