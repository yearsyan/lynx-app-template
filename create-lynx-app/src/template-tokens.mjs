/**
 * Token rules for the template snapshot, shared by the exporter
 * (scripts/export-template.mjs, repository -> snapshot) and the scaffolder
 * (src/transform.mjs, snapshot -> user app). Each rule maps a literal
 * identifier used in this repository to the placeholder written into the
 * snapshot; the {{tokenName}} names are the option keys derived in
 * src/prompt.mjs.
 *
 * Rule order matters when exporting: longer, more specific values must be
 * replaced first so overlapping identifiers cannot clobber each other.
 */
export const templateReplacements = [
  // rootProject.name is the kebab-case project name, not the PascalCase app
  // class name that LynxTemplate refers to elsewhere.
  ['rootProject.name = "LynxTemplate"', 'rootProject.name = "{{name}}"'],
  // The HarmonyOS vendor directory is the standalone "lynxapp", not the
  // com.lynxapp prefix.
  ['"vendor": "lynxapp"', '"vendor": "{{vendor}}"'],
  ['com.lynxapp.harmony', '{{harmonyBundle}}'],
  ['com.lynxapp.debug', '{{package}}.debug'],
  ['com.lynxapp', '{{package}}'],
  ['Lynx Template', '{{displayName}}'],
  ['LynxTemplate', '{{appName}}'],
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
