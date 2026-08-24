import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  autolinkNodeModulesIssues,
  loadAutolinkModules,
  resolveAutolinkSelection,
} from '../../scripts/lib/autolink-selection.mjs';
import {
  createAutolinkSelectionState,
  updateAutolinkSelectionState,
} from '../src/autolink.mjs';
import { resolveOptions } from '../src/prompt.mjs';

let modules;
const repositoryDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

test.before(async () => {
  modules = await loadAutolinkModules();
});

test('checkbox state honors opt-in defaults and keeps required modules locked', () => {
  const choices = [
    {
      name: 'navigation',
      label: 'Navigation',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: ['android', 'ios', 'harmony'],
      defaultEnabled: true,
    },
    {
      name: 'storage',
      label: 'MMKV',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: [],
      defaultEnabled: true,
    },
    {
      name: 'app-installer',
      label: 'App Installer',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: [],
      defaultEnabled: false,
    },
    {
      name: 'liquid-glass',
      label: 'Liquid Glass',
      platforms: ['ios'],
      requiredFor: [],
      defaultEnabled: true,
    },
  ];
  let state = createAutolinkSelectionState(choices, ['android']);
  assert.deepEqual(state.selected, ['navigation', 'storage']);
  assert.deepEqual(
    state.choices.map((choice) => choice.name),
    ['navigation', 'storage', 'app-installer'],
  );

  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['navigation', 'storage']);
  state = updateAutolinkSelectionState(state, 'down');
  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['navigation']);
  state = updateAutolinkSelectionState(state, 'toggle-all');
  assert.deepEqual(state.selected, ['navigation', 'storage', 'app-installer']);
});

test('default resolution excludes opt-in modules but explicit all includes them', () => {
  const defaultSelection = resolveAutolinkSelection(
    modules,
    ['android'],
    undefined,
  );
  assert.equal(defaultSelection.includes('app-installer'), false);
  assert.equal(
    resolveAutolinkSelection(modules, ['android'], 'all').includes(
      'app-installer',
    ),
    true,
  );
});

test('non-interactive CLI selection adds host-required integrations', async () => {
  const options = await resolveOptions(
    ['--yes', '--platforms', 'android', '--autolink', 'storage', 'fixture'],
    { autolinkModules: modules, resolveAutolinkSelection },
  );
  assert.equal(options.name, 'fixture');
  assert.deepEqual(options.autolinkModules, [
    'device',
    'navigation',
    'storage',
    'webview-bridge',
  ]);
});

test('installed links must match the selected modules', async () => {
  const temporaryDirectory = await mkdtemp(
    join(tmpdir(), 'lynx-autolink-install-check-'),
  );
  const scopeDirectory = join(
    temporaryDirectory,
    'node_modules',
    '@lynx-template',
  );
  try {
    await mkdir(scopeDirectory, { recursive: true });
    await writeFile(
      join(temporaryDirectory, 'node_modules', '.modules.yaml'),
      '',
    );
    await symlink(
      join(repositoryDirectory, 'autolink', 'navigation'),
      join(scopeDirectory, 'autolink-navigation'),
      'dir',
    );
    await symlink(
      join(repositoryDirectory, 'autolink', 'websocket'),
      join(scopeDirectory, 'autolink-websocket'),
      'dir',
    );

    const issues = await autolinkNodeModulesIssues(
      temporaryDirectory,
      modules,
      ['navigation', 'storage'],
    );
    assert.equal(issues.length, 2);
    assert.ok(issues.some((issue) => issue.includes('autolink-storage')));
    assert.ok(issues.some((issue) => issue.includes('autolink-websocket')));
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
