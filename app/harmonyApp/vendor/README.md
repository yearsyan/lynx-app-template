# Vendored HarmonyOS build tooling

`lynx-library-plugin` is the unmodified official Lynx Hvigor Autolink plugin
from [`lynx-family/lynx` commit `a573c3b8`](https://github.com/lynx-family/lynx/tree/a573c3b8/platform/harmony/lynx_library_plugin).
It is pinned here because `@lynx/lynx-library-plugin@0.1.0` is not yet
published in the public package registries used by this project. The root
`hvigorconfig.ts` imports it directly; replace that relative import and add
the released package to `hvigor/hvigor-config.json5` once the matching Lynx
release channel publishes it.
