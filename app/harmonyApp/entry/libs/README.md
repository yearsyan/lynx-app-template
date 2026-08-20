# Lynx GFX Harmony native libraries

The Lynx `4.2.0-nightly.202608180606.150.ga573c3b8` Harmony package declares
`liblynxgfx.so` as a dependency of `liblynx.so`, but the matching `@lynx/gfx`
HAR does not include the native binaries.

The binaries in the ABI directories are built without source changes from the
six animation sources listed by `gfx/animation/animation.gni` at upstream Lynx
commit `a573c3b8280180b59ca3da3e33d7a50192334cce`. They link against the
same-version `liblynxbase.so` shipped by this project. Remove this workaround
once the upstream Harmony package includes `liblynxgfx.so`.

SHA-256:

- `arm64-v8a/liblynxgfx.so`: `1c95abb4e31718afab306e5b7eb087c52e8a661a1fb2322bfd8b9fea9d1cfa90`
- `x86_64/liblynxgfx.so`: `043e553a7c294d451b255e2bf0233826bac7ea2998f7e12b862a7feb06a88a31`

Source: <https://github.com/lynx-family/lynx/tree/a573c3b8280180b59ca3da3e33d7a50192334cce/gfx>

Lynx is licensed under the Apache License 2.0; see the repository root
`LICENSE` file.
