# @lynx-template/autolink-liquid-glass

iOS-only Lynx native library that autolinks two UIKit controls:

- `glass-switch`: a `UISwitch`, which adopts the system Liquid Glass appearance
  on iOS 26;
- `glass-dropdown`: a menu button backed by
  `UIButtonConfiguration.glass()` and `UIMenu` on supported systems.

Both elements keep functional UIKit fallbacks below iOS 26. Android and
HarmonyOS intentionally use the Lynx-rendered controls in the consuming bundle,
so this package declares only an iOS Autolink entry.

The TypeScript entry point owns the JSX props and event contracts. Lynx
Autolink discovers the Objective-C implementations through `@LynxElement` and
registers them in `LynxGeneratedLibraryRegistry`; the host does not perform any
manual element registration.

`lynx-autolink-codegen` currently generates NativeModule specs only. It does
not generate native Element prop setters or JSX intrinsic-element types, so
those contracts remain explicit in this package.
