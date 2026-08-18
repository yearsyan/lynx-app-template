# @lynx-template/autolink-file-system

Autolinked Android/iOS implementation of the `FileSystem` Lynx module consumed
through `@lynx-app/native-bridge#fileSystem`. It combines the user-visible
system file picker with URI-aware file operations, and operates on picker URIs
rather than assuming they are ordinary file-system paths.

- `pick` opens the system file picker and returns one or more URIs.
- `stat` resolves name, MIME type and byte size when available.
- `copyToCache` streams a URI into app cache and returns a `file://` URI.
- `readText` decodes UTF-8 with a caller-controlled byte limit.
- `readBase64` returns standard Base64 with a caller-controlled byte limit.

Both capabilities are user-mediated and do not require broad storage/files
permissions:

- **Android** uses `ACTION_OPEN_DOCUMENT` (Storage Access Framework) and asks
  the provider to persist read access when supported.
- **iOS** uses `UIDocumentPickerViewController` in copy mode and copies the
  result into the app cache before returning it.

HarmonyOS ships its `FileSystem` implementation as the `harmony/` source
HAR. Its module instance obtains `UIAbilityContext` directly, so the official
global HarmonyOS Autolink provider needs no host-supplied registration object.
