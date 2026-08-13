import {
  chmod,
  copyFile,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { basename, dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const templateRoot = join(repositoryRoot, 'create-lynx-app', 'template');
const manifestPath = join(
  repositoryRoot,
  'create-lynx-app',
  'src',
  'template-manifest.json',
);

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const binaryExtensions = new Set(manifest.binaryExtensions);
const excludeNames = new Set(manifest.excludeNames);
const excludeSuffixes = manifest.excludeSuffixes;
const excludeFiles = new Set(manifest.excludeFiles);

/**
 * Real identifiers in the buildable repo become placeholders in the template
 * snapshot. Order matters: longer, more specific values are replaced first.
 */
const globalReplacements = [
  // Context-specific: rootProject.name is the kebab project name, not the
  // PascalCase app class name used elsewhere by LynxTemplate.
  ['rootProject.name = "LynxTemplate"', 'rootProject.name = "{{name}}"'],
  // Harmony vendor is the standalone "lynxapp" (not the com.lynxapp prefix).
  ['"vendor": "lynxapp"', '"vendor": "{{vendor}}"'],
  ['com.lynxapp.harmony', '{{harmonyBundle}}'],
  ['com.lynxapp.debug', '{{package}}.debug'],
  ['com.lynxapp', '{{package}}'],
  ['Lynx Template', '{{displayName}}'],
  ['LynxTemplate', '{{appName}}'],
  ['@lynx-template', '@{{scope}}'],
];

/** File-extension scoped replacements applied after the global ones. */
const scopedReplacements = {
  '.plist': [['>iosApp<', '>{{displayName}}<']],
};

function replaceAll(text, replacements) {
  let updated = text;
  for (const [from, to] of replacements) {
    updated = updated.split(from).join(to);
  }
  return updated;
}

function isBinary(path) {
  return binaryExtensions.has(extname(path).toLowerCase());
}

function isExcluded(path) {
  const name = basename(path);
  if (excludeNames.has(name)) return true;
  if (excludeFiles.has(name)) return true;
  return excludeSuffixes.some((suffix) => name.endsWith(suffix));
}

async function copyTree(sourceDir, targetDir) {
  await mkdir(targetDir, { recursive: true });
  const entries = await readdir(sourceDir, { withFileTypes: true });

  for (const entry of entries) {
    const sourcePath = join(sourceDir, entry.name);
    if (isExcluded(sourcePath)) continue;

    let targetName = replaceAll(entry.name, globalReplacements);
    // npm never packs `.gitignore` files themselves (their contents are only
    // treated as ignore rules). Rename to a plain `gitignore` so the file ships
    // inside the template; the create CLI restores the dot prefix.
    if (targetName === '.gitignore') targetName = 'gitignore';
    const targetPath = join(targetDir, targetName);
    if (entry.isDirectory()) {
      await copyTree(sourcePath, targetPath);
      continue;
    }
    if (!entry.isFile()) continue;

    const mode = (await stat(sourcePath)).mode & 0o7777;
    if (isBinary(sourcePath)) {
      await copyFile(sourcePath, targetPath);
    } else {
      let content = await readFile(sourcePath, 'utf8');
      content = replaceAll(content, globalReplacements);
      const extension = extname(sourcePath);
      if (scopedReplacements[extension]) {
        content = replaceAll(content, scopedReplacements[extension]);
      }
      await writeFile(targetPath, content, 'utf8');
    }
    await chmod(targetPath, mode);
  }
}

/**
 * The template collapses the Kotlin package directory `java/com/lynxapp` into
 * a single `java/{{package}}` directory. The create CLI expands it back into
 * dotted path segments. We post-process here so file contents (already
 * rewritten to `package {{package}}`) and directory layout stay consistent.
 */
async function collapseKotlinPackageDirs(root) {
  const targets = [];
  async function walk(directory) {
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (!entry.isDirectory()) continue;
      if (
        entry.name === 'lynxapp' &&
        basename(directory) === 'com' &&
        basename(dirname(directory)) === 'java'
      ) {
        targets.push(path);
      } else {
        await walk(path);
      }
    }
  }
  await walk(root);

  for (const lynxappDir of targets) {
    const comDir = dirname(lynxappDir);
    const javaDir = dirname(comDir);
    await rename(lynxappDir, join(javaDir, '{{package}}'));
    await rm(comDir, { recursive: true, force: true });
  }
}

async function stripRepoOnlyScript() {
  const packageFile = join(templateRoot, 'package.json');
  const content = await readFile(packageFile, 'utf8');
  const updated = content.replace(
    /\s*"template:export":\s*"node \.\/scripts\/export-template\.mjs",\n/,
    '\n',
  );
  await writeFile(packageFile, updated, 'utf8');
}

async function main() {
  await rm(templateRoot, { recursive: true, force: true });
  await copyTree(repositoryRoot, templateRoot);
  await collapseKotlinPackageDirs(templateRoot);
  await stripRepoOnlyScript();

  const rel = (p) => relative(repositoryRoot, p);
  const snapshot = templateRoot;
  console.info(`Exported template snapshot to ${rel(snapshot)}`);
  console.info(`  binary extensions: ${[...binaryExtensions].join(', ')}`);
  console.info(
    `  ${globalReplacements.length} global + ${Object.keys(scopedReplacements).length} scoped replacement rule(s) applied`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
