/**
 * Token rules for the template snapshot, shared by the exporter
 * (scripts/export-template.mjs, repository -> snapshot) and the scaffolder
 * (src/transform.mjs, snapshot -> user app). Each rule maps a literal
 * identifier used in this repository to the placeholder written into the
 * snapshot; the {{tokenName}} names are the option keys derived in
 * src/prompt.mjs.
 *
 * Every rule must match a COMPLETE identifier (or a contextual literal such
 * as `rootProject.name = "LynxTemplate"`). A bare `LynxTemplate` prefix rule
 * is forbidden: the Lynx SDK ships its own LynxTemplate* family
 * (LynxTemplateProvider, LynxTemplateResourceFetcher, LynxTemplateData, ...)
 * that tokenization must never rewrite, so app-owned names are enumerated
 * explicitly here.
 */
export const templateReplacements = [
  // rootProject.name is the kebab-case project name, not the PascalCase app
  // class name used elsewhere.
  ['rootProject.name = "LynxTemplate"', 'rootProject.name = "{{name}}"'],
  // App-owned identifiers (class names, the Android theme, a log tag). The
  // HttpService rule must run before the shorter log-tag rule.
  ['LynxTemplateHttpService', '{{appName}}HttpService'],
  ['LynxTemplateHttp', '{{appName}}Http'],
  ['LynxTemplateApplication', '{{appName}}Application'],
  ['Theme.LynxTemplate', 'Theme.{{appName}}'],
  // The HarmonyOS vendor directory is the standalone "lynxapp", not the
  // com.lynxapp prefix.
  ['"vendor": "lynxapp"', '"vendor": "{{vendor}}"'],
  // Documentation and scripts can mention the Android source path rather
  // than the dotted application ID used in source files.
  ['com/lynxapp', '{{packagePath}}'],
  ['com.lynxapp.harmony', '{{harmonyBundle}}'],
  ['com.lynxapp.debug', '{{package}}.debug'],
  ['com.lynxapp', '{{package}}'],
  ['Lynx Template', '{{displayName}}'],
  ['@lynx-template', '@{{scope}}'],
];

/** File-extension scoped rules applied after the global ones when exporting. */
export const scopedTemplateReplacements = {
  '.plist': [['>iosApp<', '>{{displayName}}<']],
};

const TOKEN_NAME = /\{\{(\w+)\}\}/g;

function referencedTokenNames() {
  const names = new Set();
  const collect = (placeholder) => {
    for (const match of placeholder.matchAll(TOKEN_NAME)) {
      names.add(match[1]);
    }
  };
  for (const [, placeholder] of templateReplacements) {
    collect(placeholder);
  }
  for (const rules of Object.values(scopedTemplateReplacements)) {
    for (const [, placeholder] of rules) {
      collect(placeholder);
    }
  }
  return names;
}

/**
 * Fail fast when a rule references a token the caller did not supply.
 * Without this check the scaffolder would silently emit literal {{token}}
 * text into generated apps whenever these rules and src/prompt.mjs drift.
 */
export function assertTokensSupplied(tokens) {
  const missing = [...referencedTokenNames()].filter(
    (name) => !(name in tokens),
  );
  if (missing.length > 0) {
    throw new Error(
      `template rules reference token(s) without a value: ${missing.join(', ')}`,
    );
  }
}
