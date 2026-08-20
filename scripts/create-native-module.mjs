import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import {
  harmonyBuildProfile,
  harmonyHvigorfile,
  harmonyModuleJson,
} from './lib/autolink-boilerplate.mjs';
import {
  fail,
  readRootPackageJson,
  repositoryDirectory,
  requireLynxVersion,
} from './lib/repo.mjs';

const contractsFile = join(
  repositoryDirectory,
  'contracts/native-modules.json',
);
const packageFile = join(repositoryDirectory, 'package.json');

const KEBAB = /^[a-z0-9][a-z0-9-]*$/;
const PASCAL = /^[A-Z][A-Za-z0-9]*$/;

function usage() {
  console.info(`usage: pnpm new:native-module <kebab-case-name> [--module-name <PascalName>]

Scaffolds a Lynx Autolink NativeModule workspace package with matching
Android, iOS and HarmonyOS stubs, a raw TypeScript contract, a
contracts/native-modules.json entry, and official Autolink metadata.
The stubs export a single ping(message, callback) method so
pnpm native:contracts:check passes immediately; replace it on all three
hosts, keeping the contract in sync.

--module-name  JS-facing module name when it differs from the kebab name
               (e.g. the mmkv package registers as KV).`);
}

function kebabToPascalCase(value) {
  return value
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

function pascalToScreamingSnake(value) {
  return value.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase();
}

function parseArguments(argv) {
  const positional = [];
  let moduleName;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '-h' || argument === '--help') {
      usage();
      process.exit(0);
    }
    if (argument === '--module-name') {
      moduleName = argv[index + 1];
      index += 1;
      continue;
    }
    positional.push(argument);
  }
  return { name: positional[0], moduleName };
}

async function readText(path, label) {
  try {
    return await readFile(path, 'utf8');
  } catch {
    fail(`cannot read ${label}; run from the repository root`);
  }
}

async function writeIfMissing(path, content, label) {
  try {
    await readFile(path, 'utf8');
    fail(`${label} already exists: ${path}`);
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content, 'utf8');
}

// Both files are biome-formatted JSON.stringify(..., 2); verified round-trip
// stable, so a full rewrite keeps `pnpm lint` green.
function insertSortedKey(object, key, value) {
  const rebuilt = {};
  let inserted = false;
  for (const [existing, existingValue] of Object.entries(object)) {
    if (!inserted && existing > key) {
      rebuilt[key] = value;
      inserted = true;
    }
    rebuilt[existing] = existingValue;
  }
  if (!inserted) rebuilt[key] = value;
  return rebuilt;
}

async function main() {
  const { name, moduleName: moduleNameOverride } = parseArguments(
    process.argv.slice(2),
  );
  if (!name || !KEBAB.test(name)) {
    usage();
    fail(
      'module name must be kebab-case, e.g. `pnpm new:native-module payment`',
    );
  }
  const moduleName = moduleNameOverride ?? kebabToPascalCase(name);
  if (!PASCAL.test(moduleName)) {
    fail(`--module-name must be PascalCase, got: ${moduleName}`);
  }

  const rootPackageJson = await readRootPackageJson();
  const sdkVersion = requireLynxVersion(rootPackageJson, 'sdkVersion');
  const harmonySdkVersion = requireLynxVersion(
    rootPackageJson,
    'harmonySdkVersion',
  );

  const directory = join(repositoryDirectory, 'autolink', name);
  const packageSegment = name.replace(/-/g, '');
  const interfaceName = `${moduleName}Module`;
  const exportName = `${pascalToScreamingSnake(moduleName)}_MODULE_NAME`;

  const contracts = JSON.parse(await readText(contractsFile, 'contracts'));
  if (contracts.modules.some((module) => module.name === moduleName)) {
    fail(`a NativeModule named ${moduleName} already exists in contracts`);
  }
  if (contracts.modules.some((module) => module.autolink?.directory === name)) {
    fail(`autolink/${name} is already registered in contracts`);
  }
  const files = {
    'package.json': `${JSON.stringify(
      {
        name: `@lynx-template/autolink-${name}`,
        description: `Autolinked ${name} module for Lynx hosts (Android, iOS & HarmonyOS)`,
        version: '1.0.0',
        private: true,
        type: 'module',
        exports: {
          '.': './src/index.ts',
        },
        files: [
          'android',
          'ios',
          'harmony',
          'src',
          'types',
          'lynx.lib.json',
          'README.md',
        ],
      },
      null,
      2,
    )}\n`,
    'lynx.lib.json': `${JSON.stringify(
      {
        platforms: {
          android: {
            packageName: `com.lynxapp.autolink.${packageSegment}`,
            sourceDir: 'android',
          },
          ios: {
            sourceDir: 'ios',
            podspecPath: `ios/lynx-app-${name}.podspec`,
          },
          harmony: {
            packageDir: 'harmony',
          },
        },
      },
      null,
      2,
    )}\n`,
    'README.md': `# autolink/${name}

The \`${moduleName}\` NativeModule, scaffolded by \`pnpm new:native-module\`.
The generated \`ping\` method echoes its message back through the standard
result envelope; replace it with real functionality on every host.

- Android: \`android/src/main/java/com/lynxapp/autolink/${packageSegment}/${interfaceName}.java\`
- iOS: \`ios/src/${interfaceName}.m\`
- HarmonyOS: \`harmony/src/main/ets/${interfaceName}.ets\` (source HAR, autolink-registered)
- Raw TypeScript contract: \`types/platform-native-module.d.ts\`

Keep the three implementations and the contract in sync —
\`pnpm native:contracts:check\` validates method names and arity.
`,
    'types/platform-native-module.d.ts': `/**
 * Raw ${moduleName} NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class ${moduleName} {
  ping(message: string, callback: (resultJSON: string) => void): void;
}
`,
    'android/build.gradle.kts': `plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.${packageSegment}"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:${sdkVersion}")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:${sdkVersion}")
}
`,
    'android/src/main/AndroidManifest.xml': `<manifest />
`,
    [`android/src/main/java/com/lynxapp/autolink/${packageSegment}/${interfaceName}.java`]: `package com.lynxapp.autolink.${packageSegment};

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * ${moduleName} scaffolded by pnpm new:native-module. ping echoes its
 * message back through the standard result envelope; replace it with real
 * functionality.
 */
@LynxNativeModule(name = ${interfaceName}.NAME)
public final class ${interfaceName} extends LynxContextModule {
    public static final String NAME = "${moduleName}";

    public ${interfaceName}(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void ping(String message, Callback callback) {
        try {
            JSONObject result = new JSONObject();
            result.put("value", message);
            callback.invoke(result.toString());
        } catch (JSONException error) {
            callback.invoke("{\\"error\\":\\"${moduleName} serialization failed\\"}");
        }
    }
}
`,
    [`ios/lynx-app-${name}.podspec`]: `Pod::Spec.new do |s|
  s.name = 'lynx-app-${name}'
  s.version = '1.0.0'
  s.summary = 'Autolinked ${moduleName} module for Lynx hosts.'
  s.homepage = 'https://github.com/lynx-family/lynx'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'Lynx Template'
  s.source = { :path => '..' }
  s.source_files = 'src/**/*.{h,m}'
  s.ios.deployment_target = '13.0'
  s.dependency 'Lynx'
end
`,
    [`ios/src/${interfaceName}.h`]: `#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as \`${moduleName}\`.
/// Declares LynxContextModule so the runtime instantiates it through
/// initWithLynxContext:, the designated initializer in the .m stub.
@interface ${interfaceName} : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
`,
    [`ios/src/${interfaceName}.m`]: `#import "${interfaceName}.h"

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as \`${moduleName}\`.
@LynxNativeModule("${moduleName}")
@implementation ${interfaceName}

+ (NSString *)name {
  return @"${moduleName}";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"ping" : NSStringFromSelector(@selector(ping:callback:)),
  };
}

- (void)ping:(NSString *)message callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *value = @{ @"value" : message ?: @"" };
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
  callback(data ? [[NSString alloc] initWithData:data
                                        encoding:NSUTF8StringEncoding]
               : @"{\\"error\\":\\"${moduleName} serialization failed\\"}");
}

@end
`,
    'harmony/oh-package.json5': `${JSON.stringify(
      {
        name: `@lynx-template/autolink-${name}`,
        version: '1.0.0',
        description: `Autolinked ${name} module for Lynx hosts (HarmonyOS source HAR)`,
        main: 'Index.ets',
        license: 'Apache-2.0',
        dependencies: {
          '@lynx/lynx': harmonySdkVersion,
        },
      },
      null,
      2,
    )}\n`,
    'harmony/build-profile.json5': harmonyBuildProfile(),
    'harmony/hvigorfile.ts': harmonyHvigorfile(),
    'harmony/Index.ets': `export { LynxLibraryProviderImpl } from './src/main/ets/LynxLibraryProviderImpl';
export { ${interfaceName} } from './src/main/ets/${interfaceName}';
`,
    'harmony/src/main/module.json5': harmonyModuleJson(name),
    'harmony/src/main/ets/LynxLibraryProviderImpl.ets': `import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ${interfaceName} } from './${interfaceName}';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(${interfaceName}.NAME, { moduleClass: ${interfaceName} });
  }
}
`,
    [`harmony/src/main/ets/${interfaceName}.ets`]: `import { LynxContext, LynxModule } from '@lynx/lynx';

/** ${moduleName} scaffolded by pnpm new:native-module; replace ping with real functionality. */
export class ${interfaceName} extends LynxModule {
  static readonly NAME: string = '${moduleName}';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  ping(message: string, callback: (resultJSON: string) => void): void {
    callback(JSON.stringify({ value: message }));
  }
}
`,
  };

  for (const [relativePath, content] of Object.entries(files)) {
    await writeIfMissing(join(directory, relativePath), content, relativePath);
  }

  // Contracts metadata: input of scripts/generate-native-contracts.mjs.
  // Pure insertion (no re-sort) keeps the diff to exactly one new entry.
  const entry = {
    name: moduleName,
    interfaceName,
    declaration: `autolink/${name}/types/platform-native-module.d.ts`,
    declarationName: moduleName,
    autolink: {
      directory: name,
      exportName,
    },
    implementations: {
      android: {
        searchRoot: `autolink/${name}/android/src/main/java`,
        fileName: `${interfaceName}.java`,
      },
      ios: `autolink/${name}/ios/src/${interfaceName}.m`,
      harmony: `autolink/${name}/harmony/src/main/ets/${interfaceName}.ets`,
    },
  };
  const insertBefore = contracts.modules.findIndex(
    (module) => module.name > moduleName,
  );
  if (insertBefore === -1) {
    contracts.modules.push(entry);
  } else {
    contracts.modules.splice(insertBefore, 0, entry);
  }
  await writeFile(
    contractsFile,
    `${JSON.stringify(contracts, null, 2)}\n`,
    'utf8',
  );

  // Root devDependency so pnpm install links the package for Lynx autolink.
  rootPackageJson.devDependencies = insertSortedKey(
    rootPackageJson.devDependencies,
    `@lynx-template/autolink-${name}`,
    'workspace:*',
  );
  await writeFile(
    packageFile,
    `${JSON.stringify(rootPackageJson, null, 2)}\n`,
    'utf8',
  );

  // All hosts discover the package from lynx.lib.json through official
  // Android, iOS and HarmonyOS Autolink tooling.
  // Generates autolink/<name>/src/index.ts and the aggregated registries.
  const generated = spawnSync(
    process.execPath,
    [join(repositoryDirectory, 'scripts/generate-native-contracts.mjs')],
    { stdio: 'inherit', cwd: repositoryDirectory },
  );
  if (generated.status !== 0) {
    fail('pnpm native:contracts:generate failed; review the stub files');
  }

  console.info(
    `Created autolink/${name} (${moduleName}) with three-host stubs.`,
  );
  console.info('\nNext steps:');
  console.info(
    '  pnpm install                # link the new workspace package',
  );
  console.info(
    '  # replace ping() in the Java, ObjC and ArkTS stubs and update',
  );
  console.info(
    '  # types/platform-native-module.d.ts — method names and arity are',
  );
  console.info('  # validated by pnpm native:contracts:check');
  console.info('  pnpm check                  # contracts, types and lint');
}

main().catch((error) => {
  console.error(
    `error: ${error instanceof Error ? error.message : String(error)}`,
  );
  process.exit(1);
});
