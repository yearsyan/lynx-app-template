# autolink/audio

The `Audio` NativeModule: local-file audio playback plus microphone
recording for Lynx hosts (Android, iOS & HarmonyOS). Commands use
error-string acknowledgements; playback events flow back as `audioPlayer`
and recording events as `audioRecorder` global events. The package root
exports the high-level `audioPlayer` and `audioRecorder` Promise APIs.

- Android: `android/src/main/java/com/lynxapp/autolink/audio/AudioModule.java`
  (framework `MediaPlayer` + `MediaRecorder`; manual audio-focus handling; no
  extra dependencies)
- iOS: `ios/src/AudioModule.m` (`AVAudioPlayer` / `AVAudioRecorder` +
  `AVAudioSession`)
- HarmonyOS: `harmony/src/main/ets/AudioModule.ets`
  (`media.AVPlayer` / `media.AVRecorder` fed by `fs.openSync` fds; source
  HAR, autolink-registered)
- Raw TypeScript contract: `types/platform-native-module.d.ts`

Playback accepts local `file://` (and Android `content://`) sources only —
the canonical URIs are the outputs of the FileSystem / AlbumUtils modules
(and of the recorder below). Four audio streams (`media` / `ambient` /
`alarm` / `notification`) route volume keys, focus policy and the iOS
silent switch consistently across hosts.

Recording captures the microphone to AAC (`.m4a`) under the host cache
directory (`LynxFiles/recordings`) and delivers a `file://` URI that plugs
straight into `audioPlayer.create()`. Grant the microphone permission first
through the Permissions module — the recorder checks, but never prompts:

```ts
await permissions.request('microphone');
const recorder = audioRecorder.create({ durationLimitMs: 60_000 });
recorder.addEventListener('progress', (event) => console.info(event.durationMs));
await recorder.start();
const { uri, durationMs, sizeBytes } = await recorder.stop();
```

Sessions support pause/resume, cancel (discards the file) and an optional
`durationLimitMs` that auto-stops with an `end` event.

Keep the three implementations and the contract in sync —
`pnpm native:contracts:check` validates method names and arity.
