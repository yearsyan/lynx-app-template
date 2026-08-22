# autolink/image-tooling

`ImageTooling` keeps image pixels on the native side while reading metadata,
resizing, cropping, composing images, and managing EXIF. It accepts the image
URIs returned by `albumUtils.pick()`, `fileSystem`, and `screenshot`.

Every operation that writes an image creates a new `file://` result under
`<cache>/LynxImages/`; the source is never changed in place.

## Inspect and resize

```ts
import { imageTooling } from '@lynx-template/autolink-image-tooling';

const info = await imageTooling.info(uri);
// { width, height, mimeType, sizeBytes }

const resized = await imageTooling.compress({
  uri,
  maxWidth: 1024,
  maxHeight: 1024, // fit inside the box, preserving aspect ratio; never upscale
  quality: 80,     // JPEG only, integer 1-100
  format: 'jpeg',  // default; 'png' preserves alpha and ignores quality
});
// { uri: 'file:///…/LynxImages/<id>-compressed.jpg', width, height, sizeBytes }
```

`info()` and all crop coordinates use oriented/display pixels: EXIF orientation
has already been applied to `width` and `height`.

## Crop one region

```ts
const cropped = await imageTooling.crop({
  uri,
  x: 120,
  y: 80,
  width: 640,
  height: 480,
  maxWidth: 320,
  maxHeight: 320,
  format: 'png',
});
```

The rectangle must be wholly inside the oriented source. `maxWidth` and
`maxHeight` apply after cropping and never enlarge a smaller crop.

## Compose images

```ts
const horizontal = await imageTooling.compose({
  images: [firstUri, secondUri, thirdUri],
  layout: 'horizontal',
  spacing: 12,
  maxWidth: 1200,
  maxHeight: 800,
});

const vertical = await imageTooling.compose({
  images: [firstUri, secondUri],
  layout: 'vertical',
  spacing: 8,
  maxWidth: 800,
  maxHeight: 1200,
});

const overlay = await imageTooling.compose({
  images: [
    firstUri,
    { uri: secondUri, x: 24, y: 32, opacity: 0.65 },
  ],
  layout: 'overlay',
  maxWidth: 1024,
  maxHeight: 1024,
  format: 'png',
});
```

- Horizontal images are placed left-to-right and top-aligned; vertical images
  are placed top-to-bottom and left-aligned.
- Overlay coordinates default to `(0, 0)`. Later entries paint above earlier
  entries. The canvas covers every layer from the top-left origin.
- `maxWidth`/`maxHeight` scale the completed canvas proportionally and never
  upscale it. Composition accepts 1-16 images.

## Read, modify, and remove EXIF

```ts
const exif = await imageTooling.readExif(uri);
// {
//   tags: { Make: '…', Model: '…', DateTimeOriginal: '…', ... },
//   gps: { latitude: 1.23, longitude: 103.45, altitude: 12.5 } | null,
// }

const tagged = await imageTooling.writeExif({
  uri,
  tags: {
    Software: 'lynx-template',
    ImageDescription: 'processed image',
  },
  gps: { latitude: 1.23, longitude: 103.45, altitude: 12.5 },
});

// A null field deletes it. gps: null deletes the complete GPS EXIF section.
const privacyCopy = await imageTooling.writeExif({
  uri: tagged.uri,
  tags: { ImageDescription: null },
  gps: null,
});

// Decode/re-encode upright pixels into a new file with all EXIF/GPS removed.
const scrubbed = await imageTooling.removeExif({
  uri,
  quality: 100,
  // format: 'jpeg' | 'png' // otherwise preserve JPEG/PNG, fall back to JPEG
});
```

`readExif()` returns decimal signed GPS coordinates. `writeExif()` preserves the
source encoding and untouched metadata while writing into a copied cache file.
When updating GPS, omitting `altitude` preserves an existing altitude and
`altitude: null` deletes only the altitude fields.
The portable tag subset is exported as `EXIF_TAGS` and contains:

`Orientation`, `ImageDescription`, `Make`, `Model`, `Software`, `Artist`,
`Copyright`, `DateTime`, `DateTimeOriginal`, `OffsetTimeOriginal`, `UserComment`,
`ExposureTime`, `FNumber`, `ISOSpeedRatings`, `FocalLength`, `LensMake`, and
`LensModel`.

Tag values use EXIF string representations. In particular, `Orientation` is
`'1'` through `'8'`; numeric fields may be decimal or rational strings according
to their EXIF field. Treat GPS as sensitive data and prefer `gps: null` or
`removeExif()` before sharing an image when location is not required.

## Limits and platform behavior

- Inputs and outputs over 50 MP are rejected; output dimensions are limited to
  16,384 pixels per side. JPEG transparency is composited onto white.
- Android accepts `content://` and `file://`. iOS accepts `file://`. HarmonyOS
  reads picker/file URIs, while EXIF modification requires a `file://` URI.
- Android uses `BitmapFactory` and AndroidX `ExifInterface`; iOS uses ImageIO and
  UIKit encoders; HarmonyOS uses ImageKit `ImageSource`, `PixelMap`, and
  `ImagePacker`.
- Cache results can be rendered directly, read through `fileSystem`, or saved
  through `albumUtils.saveToAlbum`; the system may clean the cache later.
- No additional permission is required by this module.
