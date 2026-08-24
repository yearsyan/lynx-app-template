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
const generatedWebviewContractFile = join(
  repositoryDirectory,
  'autolink/webview-bridge/src/contracts.generated.ts',
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
    const webview = module.webview ?? true;
    if (typeof webview !== 'boolean') {
      throw new ContractError(`${location}.webview must be a boolean`);
    }
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
      webview,
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

const GENERATED_AUTOLINK_BRIDGE_HELPERS = new Set([
  'completeNativeCall',
  'decodeNativeEnvelope',
  'decodeNativeValue',
  'requireNativeModule',
  'validateNativeEnvelope',
]);

async function attachAutolinkBridgeHelpers(contract) {
  for (const module of contract.modules) {
    if (module.autolink === undefined) continue;
    const path = join(
      repositoryDirectory,
      'autolink',
      module.autolink.directory,
      'src/index.ts',
    );
    let content;
    try {
      content = await readFile(path, 'utf8');
    } catch (error) {
      throw new ContractError(
        `cannot read ${repositoryRelative(path)}: ${errorMessage(error)}`,
      );
    }
    const sourceFile = ts.createSourceFile(
      path,
      content,
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TS,
    );
    if (sourceFile.parseDiagnostics.length > 0) {
      const diagnostic = sourceFile.parseDiagnostics[0];
      throw new ContractError(
        `${repositoryRelative(path)} cannot be parsed: ${ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n')}`,
      );
    }

    const helpers = new Set();
    for (const statement of sourceFile.statements) {
      if (
        !ts.isImportDeclaration(statement) ||
        !ts.isStringLiteral(statement.moduleSpecifier) ||
        statement.moduleSpecifier.text !== './bridge.generated.js'
      ) {
        continue;
      }
      const bindings = statement.importClause?.namedBindings;
      if (bindings === undefined || !ts.isNamedImports(bindings)) {
        throw new ContractError(
          `${repositoryRelative(path)} must use named imports from ./bridge.generated.js`,
        );
      }
      for (const element of bindings.elements) {
        const helper = (element.propertyName ?? element.name).text;
        if (!GENERATED_AUTOLINK_BRIDGE_HELPERS.has(helper)) {
          throw new ContractError(
            `${repositoryRelative(path)} imports unknown generated bridge helper ${helper}`,
          );
        }
        helpers.add(helper);
      }
    }
    if (!helpers.has('requireNativeModule')) {
      throw new ContractError(
        `${repositoryRelative(path)} must import requireNativeModule from ./bridge.generated.js`,
      );
    }
    module.bridgeHelpers = helpers;
  }
  return contract;
}

function generateWebviewContract(contract) {
  const modules = contract.modules.filter((module) => module.webview);
  const lines = [
    '// Generated from per-package NativeModule declarations. Do not edit.',
    '// Run `pnpm native:contracts:generate` after changing a declaration.',
    '',
    'export const NATIVE_MODULE_CONTRACT = {',
  ];
  for (const module of modules) {
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
  for (const module of modules) {
    lines.push(`  ${module.name}: NATIVE_MODULE_CONTRACT.${module.name}.name,`);
  }
  lines.push('} as const;', '');

  lines.push('export const NATIVE_MODULE_METHODS = {');
  for (const module of modules) {
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

  return lines.join('\n');
}

function generateAutolinkRawEntry(module) {
  return `// Generated from contracts/native-modules.json. Do not edit.
import type { ${module.name} as Raw${module.interfaceName} } from '../types/platform-native-module.js';

export type ${module.interfaceName} = Raw${module.interfaceName};

/** Name the native hosts register this module under. */
export const ${module.autolink.exportName} = '${module.name}' as const;
`;
}

function generateAutolinkBridgeEntry(module) {
  const helpers = module.bridgeHelpers;
  const singleLineImport = `import { ${module.autolink.exportName}, type ${module.interfaceName} } from './native.generated.js';`;
  const importStatement =
    singleLineImport.length <= 80
      ? singleLineImport
      : `import {
  ${module.autolink.exportName},
  type ${module.interfaceName},
} from './native.generated.js';`;
  const singleLineInvalidError = `          reject(new Error('${module.name} returned an invalid error value'));`;
  const invalidErrorStatement =
    singleLineInvalidError.length <= 80
      ? singleLineInvalidError
      : `          reject(
            new Error('${module.name} returned an invalid error value'),
          );`;
  const completionBlock = helpers.has('completeNativeCall')
    ? `
/** Convert the native error-string callback convention to a Promise. */
export function completeNativeCall(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        'background only';
        if (typeof error !== 'string') {
${invalidErrorStatement}
          return;
        }
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}
`
    : '';
  const decodeValueBlock =
    helpers.has('decodeNativeValue') || helpers.has('decodeNativeEnvelope')
      ? `
/** Accept structured bridge values and legacy JSON strings during migration. */
export function decodeNativeValue(value: unknown, source: string): unknown {
  'background only';
  if (typeof value !== 'string') {
    return value;
  }
  try {
    return JSON.parse(value) as unknown;
  } catch {
    throw new Error(\`\${source} returned invalid JSON\`);
  }
}
`
      : '';
  const envelopeBlock =
    helpers.has('validateNativeEnvelope') || helpers.has('decodeNativeEnvelope')
      ? `
export interface NativeResultEnvelope {
  error?: unknown;
  value?: unknown;
}

/** Validate the common structured { value, error } result envelope. */
export function validateNativeEnvelope(
  value: unknown,
  source: string,
): NativeResultEnvelope {
  'background only';
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(\`\${source} returned an invalid result\`);
  }
  return value as NativeResultEnvelope;
}
`
      : '';
  const decodeEnvelopeBlock = helpers.has('decodeNativeEnvelope')
    ? `
/** Decode a legacy JSON value, then validate its result envelope. */
export function decodeNativeEnvelope(
  value: unknown,
  source: string,
): NativeResultEnvelope {
  'background only';
  return validateNativeEnvelope(decodeNativeValue(value, source), source);
}
`
    : '';
  return `// Generated from contracts/native-modules.json. Do not edit.
${importStatement}

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): ${module.interfaceName} {
  'background only';
  const nativeModule = NativeModules[${module.autolink.exportName}] as
    | ${module.interfaceName}
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('${module.name} is not registered by the host');
  }
  return nativeModule;
}
${completionBlock}${decodeValueBlock}${envelopeBlock}${decodeEnvelopeBlock}`;
}

function generateHarmonyContract(contract) {
  const modules = contract.modules.filter((module) => module.webview);
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
  for (const module of modules) {
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
    {
      path: generatedWebviewContractFile,
      content: generateWebviewContract(contract),
    },
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
        'src/native.generated.ts',
      ),
      content: generateAutolinkRawEntry(module),
    });
    outputs.push({
      path: join(
        repositoryDirectory,
        'autolink',
        module.autolink.directory,
        'src/bridge.generated.ts',
      ),
      content: generateAutolinkBridgeEntry(module),
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
WebView RPC contract and package-local Autolink facades/bridges, then validate
enabled native implementations.

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
    const contract = await attachAutolinkBridgeHelpers(
      await attachDeclarationMethods(
        parseContract(
          await readJSON(contractFile, 'contracts/native-modules.json'),
        ),
      ),
    );
    const packageJson = await readJSON(packageFile, 'package.json');
    const platforms = enabledNativePlatforms(packageJson);
    await validateNativeImplementations(contract, platforms);
    const outputs = generatedOutputs(contract, platforms);

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
