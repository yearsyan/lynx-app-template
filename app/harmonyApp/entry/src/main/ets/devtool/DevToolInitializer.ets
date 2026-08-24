/**
 * Release-safe DevTool hook.
 *
 * The debug target replaces this file from its extended source root. Keeping
 * the default implementation dependency-free means release compilation never
 * imports the DevTool service package.
 */
export class DevToolInitializer {
  static registerService(): void {
  }
}
