import {
  abilityAccessCtrl,
  common,
  Permissions,
} from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

const READ_PASTEBOARD_PERMISSION: Permissions = 'ohos.permission.READ_PASTEBOARD';

export class NativeClipboardRegistration {
  readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }
}

/** HarmonyOS Pasteboard bridge exported to Lynx as Clipboard. */
export class ClipboardModule extends LynxModule {
  static readonly NAME: string = 'Clipboard';
  private readonly registration: NativeClipboardRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as NativeClipboardRegistration | undefined;
  }

  setString(text: string, callback: (error: string) => void): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      callback('');
    }).catch((error: Error) => {
      callback(this.errorMessage(error, 'Unable to write the clipboard'));
    });
  }

  getString(callback: (text: string | null) => void): void {
    this.readString().then((text: string | null) => {
      callback(text);
    }).catch(() => {
      // The shared bridge deliberately represents an unavailable, denied, or
      // non-text clipboard as null rather than exposing platform error shapes.
      callback(null);
    });
  }

  private async readString(): Promise<string | null> {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      if (!await systemPasteboard.hasData() ||
        !systemPasteboard.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        return null;
      }
      if (!await this.ensureReadPermission()) {
        return null;
      }
      const data = await systemPasteboard.getData();
      const text = data.getPrimaryText();
      return text.length === 0 ? null : text;
    } catch (error) {
      return null;
    }
  }

  private async ensureReadPermission(): Promise<boolean> {
    if (this.registration === undefined) {
      return false;
    }
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        this.registration.context,
        [READ_PASTEBOARD_PERMISSION],
      );
      return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      return false;
    }
  }

  private errorMessage(error: Error, fallback: string): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
