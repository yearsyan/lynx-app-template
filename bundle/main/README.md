# main bundle

The default ReactLynx bundle. Shared TypeScript, Biome, and dependency-version
configuration and release scripts live at the repository root.

## Getting Started

From the repository root:

```bash
pnpm dev:main
```

The production artifact is `dist/main.lynx.bundle`. Run the following to build
all workspace bundles and copy them into every native host:

```bash
pnpm release
```

See the repository root README for native development and OTA configuration.
