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
      name: 'router',
      label: 'Router',
      platforms: ['android', 'ios', 'harmony'],
      requiredFor: ['android', 'ios', 'harmony'],
    },
    {
      name: 'mmkv',
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
  assert.deepEqual(state.selected, ['router', 'mmkv']);
  assert.deepEqual(
    state.choices.map((choice) => choice.name),
    ['router', 'mmkv'],
  );

  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['router', 'mmkv']);
  state = updateAutolinkSelectionState(state, 'down');
  state = updateAutolinkSelectionState(state, 'toggle');
  assert.deepEqual(state.selected, ['router']);
  state = updateAutolinkSelectionState(state, 'toggle-all');
  assert.deepEqual(state.selected, ['router', 'mmkv']);
});

test('non-interactive CLI selection adds host-required integrations', async () => {
  const options = await resolveOptions(
    ['--yes', '--platforms', 'android', '--autolink', 'mmkv', 'fixture'],
    { autolinkModules: modules, resolveAutolinkSelection },
  );
  assert.equal(options.name, 'fixture');
  assert.deepEqual(options.autolinkModules, [
    'mmkv',
    'router',
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
      join(repositoryDirectory, 'autolink', 'router'),
      join(scopeDirectory, 'autolink-router'),
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
      ['router', 'mmkv'],
    );
    assert.equal(issues.length, 2);
    assert.ok(issues.some((issue) => issue.includes('autolink-mmkv')));
    assert.ok(issues.some((issue) => issue.includes('autolink-websocket')));
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
