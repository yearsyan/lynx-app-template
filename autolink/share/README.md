# @lynx-template/autolink-share

Autolinked Lynx native library that registers `Share` on Android, iOS and
HarmonyOS hosts. Bundles import `share` from this package root and call
`share.open(options)` to present the system share panel for plain text,
links and local files (Screenshot, ImageTooling and FileSystem products).

The single entry point answers a JSON envelope
`{ "value": { "code", "activityType", "message" } }` or
`{ "error": <string> }`; user-visible branches (dismissal, a concurrent
request) resolve as outcome codes instead of errors:

| Platform | Implementation | Result fidelity |
| --- | --- | --- |
| Android | `ACTION_SEND` / `ACTION_SEND_MULTIPLE` inside `Intent.createChooser` with a chosen-component `PendingIntent` (API 22+). Sandbox `file://` payloads go through the library's FileProvider (`${applicationId}.lynx.share.fileprovider`, cache + files roots); picker `content://` URIs pass through with a transient read grant (`ClipData` + `FLAG_GRANT_READ_URI_PERMISSION`) | `sent` with the chosen target's package name when the user picks one; `dismissed` best-effort when the host Activity resumes and no chosen-component broadcast arrives within a grace window (the platform reports nothing on a bare dismissal) |
| iOS | `UIActivityViewController` presented from the LynxView's top view controller, anchored as an arrowless popover on iPad; `title` is forwarded through the `subject` KVC key for Mail-like targets | Full fidelity: `completed` maps onto `sent` / `dismissed`, and the `UIActivityType` string identifies the target |
| HarmonyOS | Share Kit `systemShare.SharedData` + `ShareController.show` (`PLAIN_TEXT` / `HYPERLINK` / per-file UTD records, `BATCH` selection for multiple files) | The panel only reports that it closed (`dismiss`), never whether content reached a target: every completed interaction resolves `sent` with a `null` activityType |

Notes:

- `files` accepts 1-9 `file://` sandbox URIs (Android also `content://`);
  remote `http(s)://` payloads are rejected — download them through the
  networking layer first. iOS and HarmonyOS additionally verify the file
  exists / stays inside the sandbox. HarmonyOS runs the share panel in a
  system ability, which only resolves file URIs carrying the bundle name
  as authority; bare sandbox paths (`file:///data/storage/...`) are
  upgraded through `fileUri.getUriFromPath` automatically, and picker
  results with their own authority (`file://media/...`) pass through.
- One active `open` request at a time per page; a second concurrent call
  resolves `busy`.
- Android merges `url` into `EXTRA_TEXT` (ACTION_SEND has no link field);
  iOS passes text, link and files as separate activity items; HarmonyOS
  shares a link as a `HYPERLINK` record with `text` as its description,
  and ignores `url` when files are present (record types cannot mix).

HarmonyOS ships the `ShareModule` as the `harmony/` source HAR, registered
globally by the official HarmonyOS Hvigor Autolink provider. The share
panel runs inside a system ability, so no permission is declared.
