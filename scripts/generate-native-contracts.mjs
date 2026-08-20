import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

import {
  enabledNativePlatforms,
  SUPPORTED_NATIVE_PLATFORMS,
} from './lib/native-platforms.mjs';
import {
  errorMessage,
  repositoryDirectory,
  repositoryRelative,
  requireRecord,
} from './lib/repo.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const contractFile = join(repositoryDirectory, 'contracts/native-modules.json');
const packageFile = join(repositoryDirectory, 'package.json');
const nativeContractsPackageFile = join(
  repositoryDirectory,
  'lib/native-contracts/package.json',
);
const generatedContractFile = join(
  repositoryDirectory,
  'lib/native-contracts/src/index.ts',
);
const generatedHarmonyContractFile = join(
  repositoryDirectory,
  'app/harmonyApp/entry/src/main/ets/contracts/NativeModuleContracts.ets',
);

class ContractError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ContractError';
  }
}

function requireString(value, location) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ContractError(`${location} must be a non-empty string`);
  }
  return value;
}

function requireIdentifier(value, location) {
  const identifier = requireString(value, location);
  if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(identifier)) {
    throw new ContractError(`${location} must be a TypeScript identifier`);
  }
  return identifier;
}

function parseContract(value) {
  const root = requireRecord(value, 'contracts/native-modules.json');
  if (root.schemaVersion !== 2) {
    throw new ContractError(
      'contracts/native-modules.json#schemaVersion must be 2',
    );
  }
  if (!Array.isArray(root.modules) || root.modules.length === 0) {
    throw new ContractError(
      'contracts/native-modules.json#modules must be a non-empty array',
    );
  }

  const moduleNames = new Set();
  const interfaceNames = new Set();
  const autolinkDirectories = new Set();
  const modules = root.modules.map((rawModule, moduleIndex) => {
    const location = `contracts/native-modules.json#modules[${moduleIndex}]`;
    const module = requireRecord(rawModule, location);
    const name = requireIdentifier(module.name, `${location}.name`);
    const interfaceName = requireIdentifier(
      module.interfaceName,
      `${location}.interfaceName`,
    );
    const declaration = requireString(
      module.declaration,
      `${location}.declaration`,
    );
    const declarationName = requireIdentifier(
      module.declarationName,
      `${location}.declarationName`,
    );
    if (moduleNames.has(name)) {
      throw new ContractError(`${location}.name duplicates ${name}`);
    }
    if (interfaceNames.has(interfaceName)) {
      throw new ContractError(
        `${location}.interfaceName duplicates ${interfaceName}`,
      );
    }
    moduleNames.add(name);
    interfaceNames.add(interfaceName);

    const implementations = requireRecord(
      module.implementations,
      `${location}.implementations`,
    );
    for (const platform of SUPPORTED_NATIVE_PLATFORMS) {
      const implementation = implementations[platform];
      if (typeof implementation === 'string') {
        requireString(
          implementation,
          `${location}.implementations.${platform}`,
        );
      } else {
        const search = requireRecord(
          implementation,
          `${location}.implementations.${platform}`,
        );
        requireString(
          search.searchRoot,
          `${location}.implementations.${platform}.searchRoot`,
        );
        requireString(
          search.fileName,
          `${location}.implementations.${platform}.fileName`,
        );
      }
    }

    let autolink;
    if (module.autolink !== undefined) {
      const rawAutolink = requireRecord(
        module.autolink,
        `${location}.autolink`,
      );
      const directory = requireString(
        rawAutolink.directory,
        `${location}.autolink.directory`,
      );
      const exportName = requireIdentifier(
        rawAutolink.exportName,
        `${location}.autolink.exportName`,
      );
      if (autolinkDirectories.has(directory)) {
        throw new ContractError(
          `${location}.autolink.directory duplicates ${directory}`,
        );
      }
      autolinkDirectories.add(directory);
      autolink = { directory, exportName };
    }

    return {
      name,
      interfaceName,
      declaration,
      declarationName,
      implementations,
      autolink,
    };
  });

  return { modules };
}

function parseDeclarationMethods(sourceFile, module, path) {
  if (sourceFile.parseDiagnostics.length > 0) {
    const diagnostic = sourceFile.parseDiagnostics[0];
    throw new ContractError(
      `${repositoryRelative(path)} cannot be parsed: ${ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n')}`,
    );
  }

  const declaration = sourceFile.statements.find(
    (statement) =>
      (ts.isClassDeclaration(statement) ||
        ts.isInterfaceDeclaration(statement)) &&
      statement.name?.text === module.declarationName,
  );
  if (declaration === undefined) {
    throw new ContractError(
      `${repositoryRelative(path)} does not declare ${module.declarationName}`,
    );
  }

  const names = new Set();
  const methods = [];
  for (const member of declaration.members) {
    if (!ts.isMethodDeclaration(member) && !ts.isMethodSignature(member)) {
      continue;
    }
    if (!ts.isIdentifier(member.name)) {
      throw new ContractError(
        `${repositoryRelative(path)}#${module.declarationName} contains a non-identifier method`,
      );
    }
    const name = member.name.text;
    if (names.has(name)) {
      throw new ContractError(
        `${repositoryRelative(path)}#${module.declarationName} duplicates ${name}`,
      );
    }
    names.add(name);
    methods.push({ name, arity: member.parameters.length });
  }
  if (methods.length === 0) {
    throw new ContractError(
      `${repositoryRelative(path)}#${module.declarationName} must declare at least one method`,
    );
  }
  return methods;
}

async function attachDeclarationMethods(contract) {
  const sourceFiles = new Map();
  for (const module of contract.modules) {
    const path = join(repositoryDirectory, module.declaration);
    let sourceFile = sourceFiles.get(path);
    if (sourceFile === undefined) {
      let content;
      try {
        content = await readFile(path, 'utf8');
      } catch (error) {
        throw new ContractError(
          `cannot read ${module.declaration}: ${errorMessage(error)}`,
        );
      }
      sourceFile = ts.createSourceFile(
        path,
        content,
        ts.ScriptTarget.Latest,
        true,
        path.endsWith('.d.ts') ? ts.ScriptKind.TS : undefined,
      );
      sourceFiles.set(path, sourceFile);
    }
    module.methods = parseDeclarationMethods(sourceFile, module, path);
  }
  return contract;
}

function generateTypeScript(contract) {
  const autolinkModules = contract.modules.filter(
    (module) => module.autolink !== undefined,
  );
  autolinkModules.sort((left, right) =>
    left.interfaceName.localeCompare(right.interfaceName),
  );
  const hostModules = contract.modules.filter(
    (module) => module.autolink === undefined,
  );
  hostModules.sort((left, right) =>
    left.interfaceName.localeCompare(right.interfaceName),
  );
  const lines = [
    '// Generated from per-package NativeModule declarations. Do not edit.',
    '// Run `pnpm native:contracts:generate` after changing a declaration.',
    '',
  ];
  for (const module of autolinkModules) {
    lines.push(
      `import type { ${module.interfaceName} } from '@lynx-template/autolink-${module.autolink.directory}';`,
    );
  }
  if (hostModules.length > 0) {
    lines.push(
      `import type { ${hostModules.map((module) => module.interfaceName).join(', ')} } from './host.js';`,
    );
  }
  lines.push('', 'export type {');
  const exportedModules = [...contract.modules].sort((left, right) =>
    left.interfaceName.localeCompare(right.interfaceName),
  );
  for (const module of exportedModules) {
    lines.push(`  ${module.interfaceName},`);
  }
  lines.push('};', '', 'export const NATIVE_MODULE_CONTRACT = {');
  for (const module of contract.modules) {
    lines.push(`  ${module.name}: {`);
    lines.push(`    name: '${module.name}',`);
    lines.push('    methods: {');
    for (const method of module.methods) {
      lines.push(
        `      ${method.name}: { name: '${method.name}', arity: ${method.arity} },`,
      );
    }
    lines.push('    },');
    lines.push('  },');
  }
  lines.push('} as const;', '');

  lines.push('export const NATIVE_MODULE_NAMES = {');
  for (const module of contract.modules) {
    lines.push(`  ${module.name}: NATIVE_MODULE_CONTRACT.${module.name}.name,`);
  }
  lines.push('} as const;', '');

  lines.push('export const NATIVE_MODULE_METHODS = {');
  for (const module of contract.modules) {
    lines.push(`  ${module.name}: {`);
    for (const method of module.methods) {
      const value = `NATIVE_MODULE_CONTRACT.${module.name}.methods.${method.name}.name,`;
      const assignment = `    ${method.name}: ${value}`;
      if (assignment.length <= 80) {
        lines.push(assignment);
      } else {
        lines.push(`    ${method.name}:`, `      ${value}`);
      }
    }
    lines.push('  },');
  }
  lines.push('} as const;', '');
  lines.push(
    'export type NativeModuleName = keyof typeof NATIVE_MODULE_CONTRACT;',
    'export type NativeMethodName<Name extends NativeModuleName> =',
    '  keyof (typeof NATIVE_MODULE_METHODS)[Name] & string;',
    '',
  );

  lines.push('export interface NativeModuleRegistry {');
  for (const module of contract.modules) {
    lines.push(`  ${module.name}?: ${module.interfaceName};`);
  }
  lines.push('}', '');
  return lines.join('\n');
}

function generateAutolinkEntry(module) {
  return `// Generated from contracts/native-modules.json. Do not edit.
export type { ${module.name} as ${module.interfaceName} } from '../types/platform-native-module.js';

/** Name the native hosts register this module under. */
export const ${module.autolink.exportName} = '${module.name}' as const;
`;
}

// The generated registry imports every autolink package, so each one must be
// a declared dependency of @lynx-app/native-contracts; pnpm's strict linker
// does not tolerate imports that only resolve through hoisting. Rebuild the
// dependencies here so adding a module can never leave the manifest behind.
async function nativeContractsPackageOutput(contract) {
  const packageJson = requireRecord(
    await readJSON(
      nativeContractsPackageFile,
      'lib/native-contracts/package.json',
    ),
    'lib/native-contracts/package.json',
  );
  const existing = requireRecord(
    packageJson.dependencies,
    'lib/native-contracts/package.json#dependencies',
  );
  const dependencies = {};
  for (const [name, version] of Object.entries(existing)) {
    if (!name.startsWith('@lynx-template/autolink-')) {
      dependencies[name] = version;
    }
  }
  for (const module of contract.modules) {
    if (module.autolink === undefined) continue;
    dependencies[`@lynx-template/autolink-${module.autolink.directory}`] =
      'workspace:*';
  }
  packageJson.dependencies = Object.fromEntries(
    Object.entries(dependencies).sort(([left], [right]) =>
      left < right ? -1 : left > right ? 1 : 0,
    ),
  );
  return {
    path: nativeContractsPackageFile,
    content: `${JSON.stringify(packageJson, null, 2)}\n`,
  };
}

function generateHarmonyContract(contract) {
  const lines = [
    '// Generated from contracts/native-modules.json. Do not edit.',
    '// Run `pnpm native:contracts:generate` after changing the contract.',
    '',
    '/** Returns total native arity (including callback), or -1 if not exported. */',
    'export function nativeModuleMethodArity(',
    '  moduleName: string,',
    '  methodName: string,',
    '): number {',
    '  switch (moduleName) {',
  ];
  for (const module of contract.modules) {
    lines.push(`    case '${module.name}':`);
    lines.push('      switch (methodName) {');
    for (const method of module.methods) {
      lines.push(`        case '${method.name}':`);
      lines.push(`          return ${method.arity};`);
    }
    lines.push('        default:');
    lines.push('          return -1;');
    lines.push('      }');
  }
  lines.push('    default:', '      return -1;', '  }', '}', '');
  return lines.join('\n');
}

function generatedOutputs(contract, platforms) {
  const outputs = [
    { path: generatedContractFile, content: generateTypeScript(contract) },
  ];
  if (platforms.includes('harmony')) {
    outputs.push({
      path: generatedHarmonyContractFile,
      content: generateHarmonyContract(contract),
    });
  }
  for (const module of contract.modules) {
    if (module.autolink === undefined) continue;
    outputs.push({
      path: join(
        repositoryDirectory,
        'autolink',
        module.autolink.directory,
        'src/index.ts',
      ),
      content: generateAutolinkEntry(module),
    });
  }
  return outputs;
}

async function findFilesByName(rootDirectory, fileName) {
  const matches = [];
  const entries = await readdir(rootDirectory, { withFileTypes: true });
  for (const entry of entries) {
    const path = join(rootDirectory, entry.name);
    if (entry.isDirectory()) {
      matches.push(...(await findFilesByName(path, fileName)));
    } else if (entry.isFile() && entry.name === fileName) {
      matches.push(path);
    }
  }
  return matches;
}

async function resolveImplementation(implementation) {
  if (typeof implementation === 'string') {
    return join(repositoryDirectory, implementation);
  }
  const root = join(repositoryDirectory, implementation.searchRoot);
  let matches;
  try {
    matches = await findFilesByName(root, implementation.fileName);
  } catch (error) {
    throw new ContractError(
      `cannot search ${implementation.searchRoot}: ${errorMessage(error)}`,
    );
  }
  if (matches.length !== 1) {
    throw new ContractError(
      `expected one ${implementation.fileName} under ${implementation.searchRoot}, found ${matches.length}`,
    );
  }
  return matches[0];
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parametersAt(content, openingParenthesis) {
  let depth = 0;
  for (let index = openingParenthesis; index < content.length; index += 1) {
    const character = content[index];
    if (character === '(') depth += 1;
    if (character === ')') {
      depth -= 1;
      if (depth === 0) {
        return content.slice(openingParenthesis + 1, index);
      }
    }
  }
  throw new ContractError('method declaration has unbalanced parentheses');
}

function parameterCount(parameters) {
  const normalized = parameters.trim().replace(/,\s*$/, '');
  if (normalized.length === 0) return 0;
  let nested = 0;
  let count = 1;
  for (const character of normalized) {
    if (character === '(' || character === '[' || character === '{') {
      nested += 1;
    } else if (character === ')' || character === ']' || character === '}') {
      nested -= 1;
    } else if (character === ',' && nested === 0) {
      count += 1;
    }
  }
  return count;
}

function braceBodyAt(content, openingBrace) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = openingBrace; index < content.length; index += 1) {
    const character = content[index];
    const next = content[index + 1];
    if (lineComment) {
      if (character === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === '*' && next === '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote !== null) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (character === '/' && next === '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === '/' && next === '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character === "'" || character === '"' || character === '`') {
      quote = character;
      continue;
    }
    if (character === '{') depth += 1;
    if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return content.slice(openingBrace + 1, index);
      }
    }
  }
  throw new ContractError('class declaration has unbalanced braces');
}

function extractAndroidMethods(content) {
  const methods = new Map();
  const annotation = /@LynxMethod(?:\s*\([^)]*\))?/g;
  for (const match of content.matchAll(annotation)) {
    const start = match.index + match[0].length;
    const declaration = content
      .slice(start)
      .match(
        /^\s*(?:(?:public|protected|private|static|final|synchronized)\s+)*(?:void\s+|fun\s+)([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/,
      );
    if (declaration === null) continue;
    const openingParenthesis =
      start + declaration.index + declaration[0].lastIndexOf('(');
    methods.set(
      declaration[1],
      parameterCount(parametersAt(content, openingParenthesis)),
    );
  }
  return methods;
}

function extractIOSMethods(content) {
  const marker = content.indexOf('methodLookup');
  if (marker < 0) return new Map();
  const lookup = content.slice(marker, marker + 2500);
  const methods = new Map();
  const objectiveC =
    /@"([A-Za-z_$][A-Za-z0-9_$]*)"\s*:\s*NSStringFromSelector\(@selector\(([^)]*)\)\)/g;
  for (const match of lookup.matchAll(objectiveC)) {
    methods.set(match[1], (match[2].match(/:/g) ?? []).length);
  }
  const swift =
    /"([A-Za-z_$][A-Za-z0-9_$]*)"\s*:\s*"([A-Za-z_$][A-Za-z0-9_$]*:(?:[A-Za-z_$][A-Za-z0-9_$]*:)*)"/g;
  for (const match of lookup.matchAll(swift)) {
    methods.set(match[1], (match[2].match(/:/g) ?? []).length);
  }
  return methods;
}

function validateModuleName(content, platform, module) {
  const name = escapeRegExp(module.name);
  if (platform === 'android') {
    const pattern = new RegExp(
      `(?:String\\s+NAME|const\\s+val\\s+NAME)\\s*=\\s*"${name}"`,
    );
    return pattern.test(content);
  }
  if (platform === 'ios') {
    return (
      new RegExp(`@LynxNativeModule\\("${name}"\\)`).test(content) ||
      new RegExp(`static\\s+let\\s+name\\s*=\\s*"${name}"`).test(content)
    );
  }
  return new RegExp(
    `static\\s+readonly\\s+NAME(?::\\s*string)?\\s*=\\s*'${name}'`,
  ).test(content);
}

function compareExactMethods(actual, module, platform, path) {
  const expectedNames = module.methods.map((method) => method.name).sort();
  const actualNames = [...actual.keys()].sort();
  if (expectedNames.join('\0') !== actualNames.join('\0')) {
    throw new ContractError(
      `${repositoryRelative(path)} exports ${platform} methods [${actualNames.join(', ')}], expected [${expectedNames.join(', ')}]`,
    );
  }
  for (const method of module.methods) {
    if (actual.get(method.name) !== method.arity) {
      throw new ContractError(
        `${repositoryRelative(path)}#${method.name} has arity ${String(actual.get(method.name))}, expected ${method.arity}`,
      );
    }
  }
}

function extractHarmonyMethods(content, module, path) {
  const classMarker = new RegExp(
    `export\\s+class\\s+${escapeRegExp(module.interfaceName)}\\s+extends\\s+LynxModule`,
  );
  const classMatch = classMarker.exec(content);
  if (classMatch === null) {
    throw new ContractError(
      `${repositoryRelative(path)} does not declare ${module.interfaceName} extends LynxModule`,
    );
  }
  const openingBrace = content.indexOf(
    '{',
    classMatch.index + classMatch[0].length,
  );
  if (openingBrace < 0) {
    throw new ContractError(
      `${repositoryRelative(path)} has no body for ${module.interfaceName}`,
    );
  }
  const moduleContent = braceBodyAt(content, openingBrace);
  const methods = new Map();
  const declaration =
    /^ {2}(?:(?:public|async)\s+)*([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/gm;
  for (const methodMatch of moduleContent.matchAll(declaration)) {
    const name = methodMatch[1];
    if (name === 'constructor' || name === 'destroy') continue;
    const openingParenthesis =
      methodMatch.index + methodMatch[0].lastIndexOf('(');
    methods.set(
      name,
      parameterCount(parametersAt(moduleContent, openingParenthesis)),
    );
  }
  return methods;
}

async function validateNativeImplementations(contract, platforms) {
  for (const module of contract.modules) {
    for (const platform of platforms) {
      const path = await resolveImplementation(
        module.implementations[platform],
      );
      let content;
      try {
        content = await readFile(path, 'utf8');
      } catch (error) {
        throw new ContractError(
          `cannot read ${repositoryRelative(path)}: ${errorMessage(error)}`,
        );
      }
      if (!validateModuleName(content, platform, module)) {
        throw new ContractError(
          `${repositoryRelative(path)} does not register module name ${module.name}`,
        );
      }
      if (platform === 'android') {
        compareExactMethods(
          extractAndroidMethods(content),
          module,
          platform,
          path,
        );
      } else if (platform === 'ios') {
        compareExactMethods(extractIOSMethods(content), module, platform, path);
      } else {
        compareExactMethods(
          extractHarmonyMethods(content, module, path),
          module,
          platform,
          path,
        );
      }
    }
  }
}

async function readJSON(path, label) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    throw new ContractError(`cannot read ${label}: ${errorMessage(error)}`);
  }
}

async function checkOutputs(outputs) {
  const stale = [];
  for (const output of outputs) {
    let actual;
    try {
      actual = await readFile(output.path, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') {
        stale.push(output.path);
        continue;
      }
      throw error;
    }
    if (actual !== output.content) stale.push(output.path);
  }
  return stale;
}

async function writeOutputs(outputs) {
  for (const output of outputs) {
    await mkdir(dirname(output.path), { recursive: true });
    await writeFile(output.path, output.content, 'utf8');
  }
}

function printHelp() {
  console.info(`usage: node scripts/generate-native-contracts.mjs [--check]

Aggregate per-package TypeScript NativeModule declarations, generate the
registry and Autolink exports, then validate enabled native implementations.

options:
  --check  fail when generated files or native implementations have drifted
  -h, --help  show this help message`);
}

async function main(args = process.argv.slice(2)) {
  if (args.includes('-h') || args.includes('--help')) {
    printHelp();
    return 0;
  }
  const unknownArguments = args.filter((argument) => argument !== '--check');
  if (unknownArguments.length > 0) {
    console.error(`error: unrecognized argument: ${unknownArguments[0]}`);
    return 2;
  }

  try {
    const contract = await attachDeclarationMethods(
      parseContract(
        await readJSON(contractFile, 'contracts/native-modules.json'),
      ),
    );
    const packageJson = await readJSON(packageFile, 'package.json');
    const platforms = enabledNativePlatforms(packageJson);
    await validateNativeImplementations(contract, platforms);
    const outputs = generatedOutputs(contract, platforms);
    outputs.push(await nativeContractsPackageOutput(contract));

    if (args.includes('--check')) {
      const stale = await checkOutputs(outputs);
      if (stale.length > 0) {
        console.error('Generated Native Module contracts are out of date:');
        for (const path of stale) {
          console.error(`  - ${repositoryRelative(path)}`);
        }
        console.error('Run `pnpm native:contracts:generate` to update them.');
        return 1;
      }
      console.info(
        `Native Module contracts are up to date for: ${platforms.join(', ')}.`,
      );
      return 0;
    }

    await writeOutputs(outputs);
    console.info(
      `Generated ${outputs.length} Native Module contract file(s) and validated: ${platforms.join(', ')}.`,
    );
    return 0;
  } catch (error) {
    console.error(`error: ${errorMessage(error)}`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  process.exitCode = await main();
}
