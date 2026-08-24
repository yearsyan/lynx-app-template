import { LynxServiceCenter, LynxServiceType } from '@lynx/lynx';
import { LynxDevToolService } from '@lynx/lynx_devtool_service';

/** Debug-only Lynx DevTool service registration. */
export class DevToolInitializer {
  static registerService(): void {
    LynxServiceCenter.registerService(
      LynxServiceType.DevTool,
      LynxDevToolService.instance,
    );
  }
}
