import { join } from 'node:path';
import { stdin as input, stdout as output } from 'node:process';
import readline from 'node:readline';
import { pathToFileURL } from 'node:url';

/** Load the selection rules shipped inside the template snapshot. */
export async function loadAutolinkSupport(templateDirectory) {
  const helper = join(
    templateDirectory,
    'scripts',
    'lib',
    'autolink-selection.mjs',
  );
  return import(pathToFileURL(helper).href);
}

function selectedPlatforms(platforms) {
  return new Set(platforms);
}

export function createAutolinkSelectionState(modules, platforms) {
  const enabledPlatforms = selectedPlatforms(platforms);
  const choices = modules
    .filter((module) =>
      module.platforms.some((platform) => enabledPlatforms.has(platform)),
    )
    .map((module) => ({
      name: module.name,
      label: module.label,
      defaultEnabled: module.defaultEnabled,
      required: module.requiredFor.some((platform) =>
        enabledPlatforms.has(platform),
      ),
    }));
  return {
    choices,
    cursor: 0,
    selected: choices
      .filter((choice) => choice.required || choice.defaultEnabled)
      .map((choice) => choice.name),
  };
}

/** Pure state transition kept separate so keyboard behavior is unit-testable. */
export function updateAutolinkSelectionState(state, action) {
  const choiceCount = state.choices.length;
  if (choiceCount === 0) return state;
  if (action === 'up' || action === 'down') {
    const delta = action === 'up' ? -1 : 1;
    return {
      ...state,
      cursor: (state.cursor + delta + choiceCount) % choiceCount,
    };
  }

  const selected = new Set(state.selected);
  if (action === 'toggle') {
    const choice = state.choices[state.cursor];
    if (!choice.required) {
      if (selected.has(choice.name)) selected.delete(choice.name);
      else selected.add(choice.name);
    }
  } else if (action === 'toggle-all') {
    const optional = state.choices.filter((choice) => !choice.required);
    const allOptionalSelected = optional.every((choice) =>
      selected.has(choice.name),
    );
    for (const choice of optional) {
      if (allOptionalSelected) selected.delete(choice.name);
      else selected.add(choice.name);
    }
  } else {
    return state;
  }

  return {
    ...state,
    selected: state.choices
      .filter((choice) => selected.has(choice.name))
      .map((choice) => choice.name),
  };
}

function selectionLines(state) {
  const lines = ['Select native Autolink modules:'];
  for (const [index, choice] of state.choices.entries()) {
    const cursor = index === state.cursor ? '❯' : ' ';
    const checked = state.selected.includes(choice.name) ? 'x' : ' ';
    const required = choice.required
      ? ' (required by selected host)'
      : choice.defaultEnabled
        ? ''
        : ' (opt-in)';
    lines.push(
      `${cursor} [${checked}] ${choice.label} (${choice.name})${required}`,
    );
  }
  lines.push(
    '  ↑/↓ or j/k: move  space: toggle  a: toggle all optional  enter: confirm',
  );
  return lines;
}

/** Render a raw-mode checkbox list and return the selected module names. */
export async function promptAutolinkModules(
  modules,
  platforms,
  { inputStream = input, outputStream = output } = {},
) {
  let state = createAutolinkSelectionState(modules, platforms);
  if (state.choices.length === 0) return [];
  if (typeof inputStream.setRawMode !== 'function') {
    return state.selected;
  }

  readline.emitKeypressEvents(inputStream);
  const wasRaw = Boolean(inputStream.isRaw);
  const wasPaused = inputStream.isPaused();
  let renderedLineCount = 0;

  const render = () => {
    if (renderedLineCount > 0) {
      outputStream.write(`\x1B[${renderedLineCount}F\x1B[J`);
    }
    const lines = selectionLines(state);
    outputStream.write(`${lines.join('\n')}\n`);
    renderedLineCount = lines.length;
  };

  inputStream.setRawMode(true);
  if (wasPaused) inputStream.resume();
  render();

  return new Promise((resolve, reject) => {
    const cleanup = () => {
      inputStream.removeListener('keypress', onKeypress);
      if (!wasRaw) inputStream.setRawMode(false);
      if (wasPaused) inputStream.pause();
    };
    const onKeypress = (character, key = {}) => {
      if (key.ctrl && key.name === 'c') {
        cleanup();
        outputStream.write('\n');
        reject(new Error('Autolink module selection cancelled'));
        return;
      }
      if (key.name === 'return' || key.name === 'enter') {
        cleanup();
        resolve(state.selected);
        return;
      }

      let action;
      if (key.name === 'up' || character === 'k') action = 'up';
      else if (key.name === 'down' || character === 'j') action = 'down';
      else if (key.name === 'space' || character === ' ') action = 'toggle';
      else if (character === 'a') action = 'toggle-all';
      if (action) {
        state = updateAutolinkSelectionState(state, action);
        render();
      }
    };
    inputStream.on('keypress', onKeypress);
  });
}
