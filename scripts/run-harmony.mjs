// Build the HarmonyOS app with DevEco Studio's bundled ohpm + hvigor,
// cross-platform (Windows and macOS).
//
// Usage:
//   node scripts/run-harmony.mjs <debug|release> [extra hvigor args...]
//
// DEVECO_HOME overrides tool discovery; platform defaults:
//   Windows: C:\Program Files\Huawei\DevEco Studio
//   macOS:   /Applications/DevEco-Studio.app
//
// The package.json scripts used to call ohpm/hvigorw with POSIX-only syntax
// (`${DEVECO_HOME:-...}`, `NODE_HOME=... cmd`). This wrapper resolves the
// tools in Node so the same command runs from cmd.exe, PowerShell or bash.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { delimiter, join } from 'node:path';

import { fail, repositoryDirectory } from './lib/repo.mjs';

const isWindows = process.platform === 'win32';
const isMac = process.platform === 'darwin';

function resolveDevecoHome() {
  if (process.env.DEVECO_HOME) return process.env.DEVECO_HOME;
  if (isWindows) return 'C:\\Program Files\\Huawei\\DevEco Studio';
  if (isMac) return '/Applications/DevEco-Studio.app';
  return null;
}

function toolRoots(devecoHome) {
  // The macOS app bundle keeps its tools under Contents/.
  return {
    tools: join(devecoHome, isMac ? 'Contents/tools' : 'tools'),
    sdk: join(devecoHome, isMac ? 'Contents/sdk' : 'sdk'),
  };
}

function findTool(root, name) {
  const candidates = isWindows
    ? [join(root, `${name}.bat`), join(root, name)]
    : [join(root, name)];
  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) fail(`DevEco tool not found: ${name} (looked in ${root})`);
  return found;
}

function runTool(toolPath, args, options) {
  // Windows .bat launchers must go through cmd.exe with the path quoted
  // when it contains spaces.
  const command = isWindows ? `"${toolPath}"` : toolPath;
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    shell: isWindows,
    ...options,
  });
  if (result.error) fail(`failed to run ${toolPath}: ${result.error.message}`);
  return result.status ?? 1;
}

function main() {
  const [mode, ...extraArgs] = process.argv.slice(2);
  if (mode !== 'debug' && mode !== 'release') {
    fail('usage: node scripts/run-harmony.mjs <debug|release> [extra hvigor args...]');
  }

  const devecoHome = resolveDevecoHome();
  if (!devecoHome) {
    fail(
      'unsupported platform: set DEVECO_HOME to your DevEco Studio install',
    );
  }
  if (!existsSync(devecoHome)) {
    fail(
      `DevEco Studio not found at ${devecoHome}; set DEVECO_HOME to override`,
    );
  }

  const { tools: toolsDir, sdk: sdkDir } = toolRoots(devecoHome);
  const ohpm = findTool(join(toolsDir, 'ohpm', 'bin'), 'ohpm');
  const hvigorw = findTool(join(toolsDir, 'hvigor', 'bin'), 'hvigorw');
  const nodeHome = join(toolsDir, 'node');

  // ohpm.bat / hvigorw.bat look up node.exe through NODE_HOME or PATH.
  const env = {
    ...process.env,
    NODE_HOME: nodeHome,
    DEVECO_SDK_HOME: sdkDir,
    PATH: [nodeHome, process.env.PATH ?? ''].join(delimiter),
  };

  const projectPath = join(repositoryDirectory, 'app', 'harmonyApp');
  const common = { cwd: projectPath, env };

  console.info(`==> DevEco Studio: ${devecoHome}`);
  console.info('==> ohpm install --no-link');
  let status = runTool(ohpm, ['install', '--no-link'], common);
  if (status !== 0) fail(`ohpm install failed (exit ${status})`);

  const buildArgs = [
    'assembleHap',
    '--mode',
    'module',
    '-p',
    'product=default',
    '-p',
    `module=entry@${mode}`,
    '-p',
    `buildMode=${mode}`,
    '--no-daemon',
    ...extraArgs,
  ];
  console.info(`==> hvigorw ${buildArgs.join(' ')}`);
  status = runTool(hvigorw, buildArgs, common);
  if (status !== 0) fail(`hvigor build failed (exit ${status})`);
}

main();
