---
name: lynx-devtool
description: Inspect and interact with an already running Lynx app through agent-lynx on Android, iOS, OpenHarmony, or Desktop. Use for client or session discovery, LynxView CDP or App commands, DOM and CSS inspection, JavaScript evaluation, console logs, sources, snapshot refs and interactions, screenshots, heap or memory capture, recordings, traces, and ReactLynx component inspection or mutation. For this repository's Android host build, install, native DevTool setup, or DebugRouter connectivity, use lynx-android-cdp-debug instead.
---

# Lynx DevTool

Use `agent-lynx` to inspect a live Lynx runtime. Keep this Skill focused on
runtime operations; delegate repository-specific Android setup to
`$lynx-android-cdp-debug`.

This project copy is adapted from `@lynx-js/skill-lynx-devtool` 0.14.2
(`lynx-community/skills`, Apache-2.0). Treat `agent-lynx <command> --help`
as the source of truth when the installed CLI is newer.

## Establish an exact target

Use the installed CLI when available and fall back to `npx`:

```bash
agent-lynx <command>
npx --yes agent-lynx <command>
```

Discover clients and sessions before issuing a targeted command:

```bash
agent-lynx list-clients
agent-lynx list-sessions --client '<client-id>'
```

- Select the requested device, app process, bundle URL, and session explicitly.
- Stop and show the choices when multiple plausible targets exist.
- Refresh both IDs after an app restart or page reload; IDs are not durable.
- Preserve the same client and session throughout one diagnostic workflow.
- Treat LynxView sessions and WebView sessions differently. Use the local CDP
  references for LynxView and standard Chrome CDP documentation for WebView.

## Choose the transport deliberately

Use the shared daemon by default. Snapshot refs, annotated screenshots,
`inspect`, and ReactLynx commands require daemon state.

Use `--no-daemon` only when direct Android, iOS, OpenHarmony, or Desktop
transport is intentional or the daemon cannot see the target. Stop the daemon
before direct mode if it may own the same DebugRouter connection. Do not mix
daemon-backed refs with direct commands.

## Start with read-only evidence

Prefer read-only probes unless the user asks to navigate, interact, toggle a
switch, or mutate component data:

```bash
agent-lynx get-console --client '<client-id>' --session '<session-id>'
agent-lynx get-sources --client '<client-id>' --session '<session-id>'
agent-lynx cdp --client '<client-id>' --session '<session-id>' \
  --method DOM.getDocument '{"depth":2}'
agent-lynx evaluate '6 * 7' \
  --client '<client-id>' --session '<session-id>'
```

Evaluate side-effect-free expressions by default. Use `JSON.stringify(...)`
when a runtime does not honor `returnByValue` for objects. Inspect module-local
values from paused call frames instead of assuming they exist on `globalThis`.

## Interact through snapshot refs

Use the daemon-backed snapshot workflow for visible UI interaction:

```bash
agent-lynx snapshot
agent-lynx screenshot --annotate --json -o page.jpeg
agent-lynx tap @e3 --snapshot
agent-lynx fill @e1 'Alice'
agent-lynx clear @e1
agent-lynx scroll @e2 --direction down
agent-lynx get text @e3
agent-lynx wait --text Ready
```

Use annotated labels as `@eN` refs. Refresh the snapshot after navigation or
large UI changes. Never infer tap coordinates from screenshot pixels when a
snapshot ref is available.

## Route advanced work to references

Read only the reference needed for the requested operation:

- Before any LynxView CDP call, read the supported method matrix at
  [references/cdp/index.md](references/cdp/index.md), then its linked domain and
  method page.
- Before any App command, read
  [references/app/index.md](references/app/index.md).
- For console and parsed scripts, read
  [references/get-console.md](references/get-console.md) or
  [references/get-sources.md](references/get-sources.md).
- For screenshots and coordinate semantics, read
  [references/screenshot-annotate.md](references/screenshot-annotate.md),
  [references/take-screenshot.md](references/take-screenshot.md), or
  [references/take-content-screenshot.md](references/take-content-screenshot.md).
- For heap, global memory, switches, recording, and tracing, read
  [references/take-heap-snapshot.md](references/take-heap-snapshot.md),
  [references/cdp/memory/index.md](references/cdp/memory/index.md),
  [references/global-switch.md](references/global-switch.md),
  [references/recorder.md](references/recorder.md), or
  [references/trace.md](references/trace.md).
- For direct connector code, read
  [references/library-usage.md](references/library-usage.md).
- For discovery failures or coordinate problems, read
  [references/troubleshooting/index.md](references/troubleshooting/index.md) and
  [references/troubleshooting/click-coordinates.md](references/troubleshooting/click-coordinates.md).
- Use a matching file under `examples/` only when a complete worked sequence
  is more useful than a command reference.

## Inspect ReactLynx components

Require a dev bundle with compatible `@lynx-js/preact-devtools`, then use:

```bash
agent-lynx reactlynx tree
agent-lynx reactlynx find '<pattern>'
agent-lynx reactlynx component @c3
agent-lynx reactlynx link @e7
```

Keep `@cN` labels tied to the daemon's cached tree generation. Refresh after
page replacement or when a cached lookup fails. Run `update-prop`,
`update-state`, or `update-context` only when the user explicitly requests
a mutation.

## Report verifiable results

Report the platform and device, client metadata, session ID and URL, VM thread,
commands used, relevant JSON fields, and absolute paths for generated artifacts.
Separate observed results from supported-but-untested capabilities.
