import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { repositoryDirectory } from './lib/repo.mjs';

const workspaceDirectory = join(repositoryDirectory, 'bundle');
const name = process.argv[2];

if (!name || !/^[a-z0-9][a-z0-9-]*$/.test(name)) {
  throw new Error('Usage: pnpm new:bundle <kebab-case-name>');
}

const directory = join(workspaceDirectory, name);
await mkdir(join(directory, 'src'), { recursive: true });

// The rspeedy config comes from @lynx-template/bundle-config so every bundle
// shares one output/plugins setup and one engineVersion source (the root
// package.json). Add plugins per bundle by editing lynx.config.ts there.
const files = {
  'package.json': `${JSON.stringify(
    {
      name: `@lynx-template/${name}`,
      version: '1.0.0',
      private: true,
      type: 'module',
      lynxBundle: { name, entry: 'main' },
      scripts: {
        build: 'rspeedy build',
        dev: 'rspeedy dev',
        preview: 'rspeedy preview',
        typecheck: 'tsc -b',
      },
      dependencies: { '@lynx-js/react': 'catalog:' },
      devDependencies: {
        '@lynx-js/preact-devtools': 'catalog:',
        '@lynx-js/rspeedy': 'catalog:',
        '@lynx-js/types': 'catalog:',
        '@lynx-template/bundle-config': 'workspace:*',
        '@types/react': 'catalog:',
      },
    },
    null,
    2,
  )}\n`,
  'lynx.config.ts': `import { defineBundleConfig } from '@lynx-template/bundle-config'\n\nexport default defineBundleConfig()\n`,
  'tsconfig.json': `{
  "extends": "../../tsconfig.base.json",
  "files": [],
  "references": [
    { "path": "./tsconfig.node.json" },
    { "path": "./src" }
  ]
}\n`,
  'tsconfig.node.json': `{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "composite": true,
    "erasableSyntaxOnly": true,
    "lib": ["ES2023"],
    "module": "Node16",
    "moduleResolution": "Node16",
    "noEmit": true,
    "target": "ES2022"
  },
  "include": ["./lynx.config.ts"]
}\n`,
  'src/tsconfig.json': `{
  "extends": "../../../tsconfig.lynx.json",
  "compilerOptions": { "composite": true },
  "include": ["./**/*.ts", "./**/*.tsx"]
}\n`,
  'src/rspeedy-env.d.ts': `/// <reference types="@lynx-js/rspeedy/client" />\n\nexport {}\n`,
  'src/index.tsx': `import '@lynx-js/preact-devtools'\nimport '@lynx-js/react/debug'\nimport { root } from '@lynx-js/react'\n\nimport './style.css'\n\nfunction App() {\n  return <view className='page'><text className='title'>${name}</text></view>\n}\n\nroot.render(<App />)\n\nif (import.meta.webpackHot) import.meta.webpackHot.accept()\n`,
  'src/style.css': `.page {\n  align-items: center;\n  background-color: #10131a;\n  display: flex;\n  height: 100vh;\n  justify-content: center;\n}\n\n.title {\n  color: #ffffff;\n  font-size: 36px;\n  font-weight: 700;\n}\n`,
};

await Promise.all(
  Object.entries(files).map(([path, content]) =>
    writeFile(join(directory, path), content),
  ),
);

console.info(`Created bundle/${name}. Run pnpm install before developing it.`);
