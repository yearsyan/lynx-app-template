import {
  chmod,
  copyFile,
  mkdir,
  readdir,
  readFile,
  stat,
  writeFile,
} from 'node:fs/promises';
import { extname, join } from 'node:path';

import manifest from './template-manifest.json' with { type: 'json' };

const binaryExtensions = new Set(manifest.binaryExtensions);

/**
 * Replace every {{token}} in the given string. Tokens are sorted longest-first
 * so overlapping names cannot collide (e.g. {{name}} vs {{appName}}).
 */
function replaceTokens(text, tokens) {
  const entries = Object.entries(tokens).sort(
    (a, b) => b[0].length - a[0].length,
  );
  let updated = text;
  for (const [key, value] of entries) {
    updated = updated.split(`{{${key}}}`).join(value);
  }
  return updated;
}

function isBinary(path) {
  return binaryExtensions.has(extname(path).toLowerCase());
}

/**
 * Copy the tokenized template into targetDir, replacing tokens in text file
 * contents and in file/directory names, and expanding the collapsed Kotlin
 * package directory `{{package}}` back into dotted path segments.
 */
export async function materializeTree(sourceDir, targetDir, tokens) {
  await mkdir(targetDir, { recursive: true });
  const entries = await readdir(sourceDir, { withFileTypes: true });

  for (const entry of entries) {
    const sourcePath = join(sourceDir, entry.name);

    if (entry.isDirectory() && entry.name === '{{package}}') {
      const nested = tokens.package.split('.');
      let destination = targetDir;
      for (const segment of nested) {
        destination = join(destination, segment);
        await mkdir(destination, { recursive: true });
      }
      await materializeTree(sourcePath, destination, tokens);
      continue;
    }

    let targetName = replaceTokens(entry.name, tokens);
    // The export step ships `.gitignore` files as plain `gitignore` (npm drops
    // dotfiles named .gitignore). Restore the leading dot in the generated app.
    if (targetName === 'gitignore') targetName = '.gitignore';
    const targetPath = join(targetDir, targetName);

    if (entry.isDirectory()) {
      await materializeTree(sourcePath, targetPath, tokens);
      continue;
    }
    if (!entry.isFile()) continue;

    const mode = (await stat(sourcePath)).mode & 0o7777;
    if (isBinary(sourcePath)) {
      await copyFile(sourcePath, targetPath);
    } else {
      const content = replaceTokens(await readFile(sourcePath, 'utf8'), tokens);
      await writeFile(targetPath, content, 'utf8');
    }
    await chmod(targetPath, mode);
  }
}
