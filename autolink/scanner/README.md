# @lynx-template/autolink-scanner

Autolinked Lynx native library that registers `Scanner` on Android and iOS
hosts. Bundles consume it through `@lynx-app/native-bridge#scanner`.

Both entry points answer a JSON envelope
`{ "value": { "code", "content", "format", "message" } }` or
`{ "error": <string> }`; user-visible branches (cancel, permission denial,
no code in an image) resolve as outcome codes instead of errors:

| Method | Android | iOS |
| --- | --- | --- |
| `scan` | full-screen library `ScannerActivity`: CameraX preview + ImageAnalysis analyzed by ML Kit barcode scanning (bundled, offline, no Play Services dependency). Requests the `CAMERA` runtime permission itself and reports `permissionDenied` when denied | full-screen `AVCaptureSession` + `AVCaptureMetadataOutput` view controller presented from the LynxView's window. Requests camera access via `AVCaptureDevice` and reports `permissionDenied` when denied |
| `scanFromImage` | ML Kit `InputImage.fromFilePath` over `content://` / `file://` URIs (works with `albumUtils.pick()` results), off the main thread | Vision `VNDetectBarcodesRequest` over the `file://` image (album picker results are already copied into the cache), off the main thread |

Notes:

- The Android library manifest declares `CAMERA` plus a non-required
  `android.hardware.camera` feature, both merged into the host app; the
  iOS host must declare `NSCameraUsageDescription` itself.
- One active `scan` request at a time; a second concurrent call resolves
  `busy`.
- Unified `format` values: `qr_code`, `aztec`, `codabar`, `code39`,
  `code93`, `code128`, `data_matrix`, `ean_8`, `ean_13`, `itf`, `pdf417`,
  `upc_a`, `upc_e`, `unknown` (iOS reports UPC-A as `ean_13`, matching
  AVFoundation).

HarmonyOS hosts are **not** covered by Lynx Autolink and manually register
their `ScannerModule` from `app/harmonyApp`. It launches the Scan Kit
default system scan page (`scanBarcode.startScanForResult`) — no camera
permission required because the page runs inside a system ability — and
decodes images with `detectBarcode.decode`.
