# @lynx-template/autolink-back

Package-owned system Back interception for Lynx hosts. Bundles import
`backStack` from `@lynx-template/autolink-back` or `useBackInterceptor` from
`@lynx-template/autolink-back/react`; the raw `Back.setEnabled` contract and
its Promise/event facade stay beside the three native implementations.

- Android uses the hosting `FragmentActivity`'s AndroidX
  `OnBackPressedDispatcher`. Android 14+ emits predictive start, progress,
  cancel and commit; older releases emit a discrete start and commit.
- iOS finds the owning `UIViewController` through the LynxView responder
  chain, coordinates the navigation controller's native pop gesture and emits
  progress from a leading-edge pan.
- HarmonyOS emits discrete start and commit events. ArkUI has no public Back
  progress callback, so the host forwards its declarative `onBackPress` event
  to the package-owned route controller.

Native interception is enabled only while the TypeScript LIFO stack contains
at least one entry. With an empty stack, each platform keeps its normal system
navigation behavior.
