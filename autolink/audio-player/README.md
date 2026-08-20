# autolink/audio-player

The `AudioPlayer` NativeModule: local-file audio playback for Lynx hosts
(Android, iOS & HarmonyOS). Commands use error-string acknowledgements and
state/progress updates flow back as `audioPlayer` global events; the
high-level `audioPlayer` API lives in `@lynx-app/native-bridge`.

- Android: `android/src/main/java/com/lynxapp/autolink/audioplayer/AudioPlayerModule.java`
  (framework `MediaPlayer` + manual audio-focus handling; no extra dependencies)
- iOS: `ios/src/AudioPlayerModule.m` (`AVAudioPlayer` + `AVAudioSession`)
- HarmonyOS: `harmony/src/main/ets/AudioPlayerModule.ets`
  (`media.AVPlayer` fed by `fs.openSync` fds; source HAR, autolink-registered)
- Raw TypeScript contract: `types/platform-native-module.d.ts`

Local `file://` (and Android `content://`) sources only — the canonical URIs
are the outputs of the FileSystem / AlbumUtils modules. Four audio streams
(`media` / `ambient` / `alarm` / `notification`) route volume keys, focus
policy and the iOS silent switch consistently across hosts.

Keep the three implementations and the contract in sync —
`pnpm native:contracts:check` validates method names and arity.
