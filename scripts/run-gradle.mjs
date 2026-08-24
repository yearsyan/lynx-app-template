// Build an Android project with the Gradle wrapper, cross-platform.
//
// Usage:
//   node scripts/run-gradle.mjs <project-dir> <gradle task> [gradle args...]
//
// The package.json scripts used to call `./app/<project>/gradlew` directly,
// which only works in a POSIX shell. This wrapper picks gradlew.bat on
// Windows and the POSIX gradlew script elsewhere, so the same script runs
// from cmd.exe, PowerShell or bash.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

import { fail, repositoryDirectory } from './lib/repo.mjs';

const isWindows = process.platform === 'win32';

function main() {
  const [projectDir, ...gradleArgs] = process.argv.slice(2);
  if (!projectDir || gradleArgs.length === 0) {
    fail(
      'usage: node scripts/run-gradle.mjs <project-dir> <gradle task> [gradle args...]',
    );
  }

  const projectPath = join(repositoryDirectory, 'app', projectDir);
  const launcher = join(projectPath, isWindows ? 'gradlew.bat' : 'gradlew');
  if (!existsSync(launcher)) {
    fail(`gradle wrapper not found: ${launcher}`);
  }

  // cmd.exe cannot execute a .bat path that contains spaces unless it is
  // quoted; the POSIX gradlew script is invoked directly by bash/sh.
  const command = isWindows ? `"${launcher}"` : launcher;
  const result = spawnSync(command, gradleArgs, {
    cwd: projectPath,
    stdio: 'inherit',
    shell: isWindows,
  });
  if (result.error) {
    fail(`failed to run gradle: ${result.error.message}`);
  }
  process.exit(result.status ?? 1);
}

main();
