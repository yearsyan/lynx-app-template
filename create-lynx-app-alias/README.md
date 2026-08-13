# @lynfe/create-lynx-app

Thin `npm create` alias for [`@lynfe/lynx-app`](https://www.npmjs.com/package/@lynfe/lynx-app).

`npm create <initializer>` prepends `create-` to the initializer's package
name, so `npm create @lynfe/lynx-app` resolves to this package. Its `bin`
delegates to the real scaffolder, which materializes the multi-platform Lynx
4.0 host template.

## Usage

```bash
npm create @lynfe/lynx-app my-app
# equivalent to
pnpm dlx @lynfe/lynx-app my-app
```

See `@lynfe/lynx-app` for flags and the full list of supported options.
