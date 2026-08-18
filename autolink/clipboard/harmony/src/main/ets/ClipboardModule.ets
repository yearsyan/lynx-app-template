import { pasteboard } from '@kit.BasicServicesKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

/** HarmonyOS Pasteboard bridge exported to Lynx as Clipboard. */
export class ClipboardModule extends LynxModule {
  static readonly NAME: string = 'Clipboard';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
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
      const data = await systemPasteboard.getData();
      const text = data.getPrimaryText();
      return text.length === 0 ? null : text;
    } catch (error) {
      return null;
    }
  }

  private errorMessage(error: Error, fallback: string): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
