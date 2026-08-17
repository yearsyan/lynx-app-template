# @lynx-template/autolink-album-utils

Autolinked Lynx native library that registers `AlbumUtils` on
Android and iOS. Bundles consume it through
`@lynx-app/native-bridge#albumUtils`.

- `pick` selects one or more images from the system album.
- `saveToAlbum` writes an image URI into the system album.

Platform behavior:

- **Android** picks through the AndroidX Photo Picker contract. It prefers the
  system Photo Picker and falls back to the Storage Access Framework on devices
  where Photo Picker is unavailable, so no broad media/storage permission is
  needed. Saving uses a MediaStore insert on Android 10+ (no permission) and
  fails with a clear error below Android 10.
- **iOS 14+** picks with `PHPickerViewController` without Photos authorization.
  **iOS 13** falls back to `UIImagePickerController`, which requires the host's
  `NSPhotoLibraryUsageDescription` and runtime Photos authorization; this
  fallback supports only a single selection. Saving uses an add-only
  `PHAssetCreationRequest`; the host must declare
  `NSPhotoLibraryAddUsageDescription`.

HarmonyOS is not covered by Lynx Autolink and manually registers its
`PhotoViewPicker` implementation from `app/harmonyApp`.
