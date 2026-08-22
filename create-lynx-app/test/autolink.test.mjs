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

test('checkbox state defaults to all and keeps required modules locked', () => {
  const choices = [
    {
      name: 'navigation',
      label: 'Navigation',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: ['android', 'ios', 'harmony'],
    },
    {
      name: 'storage',
      label: 'MMKV',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: [],
    },
    {
      name: 'liquid-glass',
      label: 'Liquid Glass',
      platforms: ['ios'],
      requiredFor: [],
    },
  ];
  let state = createAutolinkSelectionState(choices, ['android']);
  assert.deepEqual(state.selected, ['navigation', 'storage']);
  assert.deepEqual(
    state.choices.map((choice) => choice.name),
    ['navigation', 'storage'],
  );

  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['navigation', 'storage']);
  state = updateAutolinkSelectionState(state, 'down');
  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['navigation']);
  state = updateAutolinkSelectionState(state, 'toggle-all');
  assert.deepEqual(state.selected, ['navigation', 'storage']);
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
