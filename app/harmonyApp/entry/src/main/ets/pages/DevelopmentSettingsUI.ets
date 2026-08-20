/**
 * Default no-op development settings UI. The debug target's extended source
 * root (src/debug) overrides this file at the same relative path with the real
 * page; here the entry renders nothing, so the page can never open in release.
 */
@Component
export struct DevelopmentSettingsEntry {
  onOpen: () => void = (): void => {};

  build() {
  }
}

@Component
export struct DevelopmentSettingsPage {
  onClose: (changed: boolean) => void = (_changed: boolean): void => {};

  build() {
  }
}
