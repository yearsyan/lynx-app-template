# @sairo/create-lynx-app

Thin `npm create` alias for [`@sairo/lynx-app`](https://www.npmjs.com/package/@sairo/lynx-app).

`npm create <initializer>` prepends `create-` to the initializer's package
name, so `npm create @sairo/lynx-app` resolves to this package. Its `bin`
delegates to the real scaffolder, which materializes the multi-platform Lynx
4.0 host template.

## Usage

```bash
npm create @sairo/lynx-app my-app
# equivalent to
pnpm dlx @sairo/lynx-app my-app
```

See `@sairo/lynx-app` for flags and the full list of supported options.
