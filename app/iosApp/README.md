# iOS host

Swift/UIKit host based on the official Lynx 4.0 integration reference.

```bash
pod install
open iosApp.xcworkspace
```

Set `LYNX_DEV_BUNDLE_URL` in the Run scheme for local development. The app falls
back to its verified Application Support cache and then the embedded
`main.lynx.bundle`.
