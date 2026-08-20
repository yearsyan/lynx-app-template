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
--autolink mmkv,toast         # native modules to enable (default all applicable)
--yes                         # skip prompts, use defaults/flags
```

Interactive runs show a checkbox TUI after the platform questions. Every
applicable Autolink module starts selected; use the arrow keys (or `j`/`k`),
space, `a`, and enter to adjust and confirm the list. `--autolink all` and
`--autolink none` are also accepted for non-interactive runs. Host-required
integrations are always added: Router on every host, and WebView bridge when
Android or iOS is selected.

The generated project keeps the same layout as this template: `bundle/*` and
`lib/*` are pnpm workspaces, and the selected native hosts live under `app/`.
Platform and module selections are recorded in
`package.json#nativeApp.platforms` and `nativeApp.autolinkModules`. Only
selected Autolink packages remain root dependencies, so the official native
scanners link only those packages. Module sources and TypeScript contracts stay
in the generated repository so the selection can be changed later with
`pnpm native:autolink:apply` followed by `pnpm install`.

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
