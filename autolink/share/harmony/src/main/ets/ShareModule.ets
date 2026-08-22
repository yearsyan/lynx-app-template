import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

/** Options forwarded by the shared TypeScript bridge. */
export interface NativeShareOptions {
  title: string | null;
  text: string | null;
  url: string | null;
  files: string[];
}

class ShareValue {
  code: string;
  activityType: string | null;
  message: string;

  constructor(code: string, activityType: string | null, message: string = '') {
    this.code = code;
    this.activityType = activityType;
    this.message = message;
  }
}

class ShareEnvelope {
  value: ShareValue | null;
  error: string;

  constructor(value: ShareValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/**
 * System share panel exported to Lynx as Share, built on Share Kit's
 * `systemShare`. The panel runs on the system side and needs no permission;
 * it only reports that it closed (`dismiss`), never whether the content
 * reached a target, so every completed interaction resolves `sent` with a
 * null activityType and the limitation is spelled out in the message.
 */
export class ShareModule extends LynxModule {
  static readonly NAME: string = 'Share';
  private readonly abilityContext: common.UIAbilityContext;
  private isSharing: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.abilityContext = getContext(this) as common.UIAbilityContext;
  }

  share(options: NativeShareOptions, callback: (resultJSON: string) => void): void {
    if (this.isSharing) {
      callback(this.encodeOutcome('busy', 'Another share request is already active'));
      return;
    }
    let data: systemShare.SharedData;
    let fileCount: number;
    try {
      const files: string[] = this.validFiles(options);
      fileCount = files.length;
      data = this.buildSharedData(options, files);
    } catch (error) {
      callback(this.encodeError(this.errorMessage(error)));
      return;
    }
    this.isSharing = true;
    let settled: boolean = false;
    const settle = (resultJSON: string): void => {
      if (settled) {
        return;
      }
      settled = true;
      this.isSharing = false;
      callback(resultJSON);
    };
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    controller.on('dismiss', () => {
      settle(this.encodeOutcome(
        'sent', 'Share panel closed; HarmonyOS does not report the share result'));
    });
    controller.show(this.abilityContext, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: fileCount > 1
        ? systemShare.SelectionMode.BATCH
        : systemShare.SelectionMode.SINGLE,
    }).catch((error: BusinessError) => {
      settle(this.encodeError(
        this.errorMessage(error, 'Unable to open the share panel')));
    });
  }

  private buildSharedData(
    options: NativeShareOptions,
    files: string[],
  ): systemShare.SharedData {
    const title: string = this.optionalText(options.title);
    const text: string = this.optionalText(options.text);
    const url: string = this.optionalText(options.url);
    if (files.length > 0) {
      const data: systemShare.SharedData = new systemShare.SharedData(
        this.fileRecord(files[0], title, text));
      for (let index = 1; index < files.length; index += 1) {
        data.addRecord(this.fileRecord(files[index], '', ''));
      }
      return data;
    }
    if (url.length > 0) {
      const scheme: string = url.split(':')[0].toLowerCase();
      if (scheme === 'javascript' || scheme === 'data') {
        throw new Error('Share url scheme is not allowed');
      }
      return new systemShare.SharedData(this.contentRecord(
        utd.UniformDataType.HYPERLINK, url, title, text));
    }
    if (text.length === 0) {
      throw new Error('Share requires a non-empty text, url or files payload');
    }
    return new systemShare.SharedData(this.contentRecord(
      utd.UniformDataType.PLAIN_TEXT, text, title, ''));
  }

  private contentRecord(
    recordUtd: string,
    content: string,
    title: string,
    description: string,
  ): systemShare.SharedRecord {
    const record: systemShare.SharedRecord = {
      utd: recordUtd,
      content,
    };
    if (title.length > 0) {
      record.title = title;
    }
    if (description.length > 0) {
      record.description = description;
    }
    return record;
  }

  private fileRecord(
    uri: string,
    title: string,
    description: string,
  ): systemShare.SharedRecord {
    const record: systemShare.SharedRecord = {
      utd: this.utdForFile(uri),
      uri,
    };
    if (title.length > 0) {
      record.title = title;
    }
    if (description.length > 0) {
      record.description = description;
    }
    return record;
  }

  /** Share Kit records reference sandbox files; picker URIs do not qualify. */
  private validFiles(options: NativeShareOptions): string[] {
    if (options.files === undefined || options.files === null) {
      return [];
    }
    const files: string[] = [];
    for (const entry of options.files) {
      if (typeof entry !== 'string') {
        continue;
      }
      const uri: string = entry.trim();
      if (uri.length === 0) {
        continue;
      }
      if (!uri.startsWith('file://')) {
        throw new Error(`Share reads sandbox file:// URIs on HarmonyOS: ${uri}`);
      }
      files.push(this.shareableFileUri(uri));
    }
    return files;
  }

  /**
   * The share panel runs in a system process and only resolves file:// URIs
   * whose authority is this app's bundle name (the form produced by
   * `fileUri.getUriFromPath`). Bare sandbox paths such as
   * `file:///data/storage/el2/base/cache/...` make the panel fail with a
   * "Parse data failed" error and close immediately, so upgrade them here.
   */
  private shareableFileUri(uri: string): string {
    const remainder: string = uri.substring('file://'.length);
    if (!remainder.startsWith('/')) {
      return uri;
    }
    try {
      return fileUri.getUriFromPath(remainder);
    } catch (error) {
      throw new Error(
        `Share cannot expose the sandbox file ${uri}: ${this.errorMessage(error as Error)}`,
      );
    }
  }

  private optionalText(value: string | null): string {
    return value === undefined || value === null ? '' : value.trim();
  }

  private utdForFile(uri: string): string {
    const name: string = uri.split('/').pop() ?? uri;
    const dot: number = name.lastIndexOf('.');
    const suffix: string = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    switch (suffix) {
      case 'png':
        return utd.UniformDataType.PNG;
      case 'jpg':
      case 'jpeg':
        return utd.UniformDataType.JPEG;
      case 'gif':
        return utd.UniformDataType.GIF;
      case 'webp':
      case 'bmp':
      case 'heic':
      case 'svg':
        return utd.UniformDataType.IMAGE;
      case 'mp4':
      case 'mov':
        return utd.UniformDataType.VIDEO;
      case 'mp3':
      case 'm4a':
      case 'aac':
      case 'wav':
        return utd.UniformDataType.AUDIO;
      case 'pdf':
        return utd.UniformDataType.PDF;
      default:
        return utd.UniformDataType.FILE;
    }
  }

  private encodeOutcome(code: string, message: string = ''): string {
    return JSON.stringify(new ShareEnvelope(new ShareValue(code, null, message)));
  }

  private encodeError(message: string): string {
    return JSON.stringify(new ShareEnvelope(null, message));
  }

  private errorMessage(error: Error, fallback: string = 'Share failed'): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
