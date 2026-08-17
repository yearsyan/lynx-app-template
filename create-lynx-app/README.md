# @lynfe/lynx-app

Scaffold a multi-platform Lynx 4.0 host (Android / iOS / HarmonyOS) from the
shared ReactLynx template.

## Usage

```bash
pnpm dlx @lynfe/lynx-app my-app
# or
npx @lynfe/lynx-app my-app
```

Flags:

```bash
--bundle-id com.acme.myapp   # reverse-DNS bundle ID (default com.<name>)
--scope acme                  # npm scope, no leading @ (default lynfe)
--display-name "My App"       # user-visible name (default derived from name)
--platforms android,ios       # comma-separated subset (default all three)
--yes                         # skip prompts, use defaults/flags
```

The generated project keeps the same layout as this template: `bundle/*` and
`lib/*` are pnpm workspaces, and the selected native hosts live under `app/`.
The selection is recorded in `package.json#nativeApp.platforms`; scripts such
as `native:check`, `native:contracts:check`, and `sync:native` only touch those
hosts, and build commands for omitted platforms are removed.

## npm create

`npm create <pkg>` resolves to the `create-<pkg>` package name, so the exact
`npm create @lynfe/lynx-app` syntax requires a thin alias package
`@lynfe/create-lynx-app` whose `bin` re-exports this entry point. Until that
alias is published, use `pnpm dlx @lynfe/lynx-app` or
`npx @lynfe/lynx-app`.

## Publishing

1. Build the template snapshot from the source repository:

   ```bash
   node scripts/export-template.mjs
   ```

   This regenerates `create-lynx-app/template/` with `{{token}}` placeholders.

2. Register the scope and publish (scoped packages default to private, so the
   `publishConfig.access` is already set to `public`):

   ```bash
   npm adduser
   npm publish
   ```

The `@lynfe` scope is claimed automatically by publishing the first
`@lynfe/*` package; no separate scope registration step is required.
