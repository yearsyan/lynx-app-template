import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

/** Carries the UIAbilityContext the system scan page is launched from. */
export class ScannerRegistration {
  readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }
}

class ScanValue {
  code: string;
  content: string | null;
  format: string | null;
  message: string;

  constructor(
    code: string,
    content: string | null,
    format: string | null,
    message: string = '',
  ) {
    this.code = code;
    this.content = content;
    this.format = format;
    this.message = message;
  }
}

class ScanEnvelope {
  value: ScanValue | null;
  error: string;

  constructor(value: ScanValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/**
 * QR and barcode scanning exported to Lynx as Scanner. `scan` launches the
 * Scan Kit default system scan page through `scanBarcode.startScanForResult`;
 * that page lives inside a system ability, so no camera permission is
 * required. `scanFromImage` decodes a local image URI (a PhotoViewPicker or
 * in-sandbox file URI) with `detectBarcode.decode`, which is equally
 * permission-free.
 */
export class ScannerModule extends LynxModule {
  static readonly NAME: string = 'Scanner';
  private readonly registration: ScannerRegistration | undefined;
  private isScanning: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as ScannerRegistration | undefined;
  }

  scan(callback: (resultJSON: string) => void): void {
    if (this.registration === undefined) {
      callback(this.encodeError('Scanner has no UIAbilityContext'));
      return;
    }
    if (this.isScanning) {
      callback(this.encodeOutcome(
        'busy', null, null, 'Another scanner request is already active'));
      return;
    }
    this.isScanning = true;
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: false,
    };
    scanBarcode.startScanForResult(this.registration.context, options)
      .then((result: scanBarcode.ScanResult) => {
        this.isScanning = false;
        callback(this.encodeOutcome(
          'success', result.originalValue, this.formatName(result.scanType)));
      })
      .catch((error: BusinessError) => {
        this.isScanning = false;
        if (error.code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
          callback(this.encodeOutcome('userCancel', null, null));
          return;
        }
        callback(this.encodeError(
          this.errorMessage(error, 'Unable to open the scanner')));
      });
  }

  scanFromImage(uri: string, callback: (resultJSON: string) => void): void {
    const imageURI: string = uri.trim();
    if (imageURI.length === 0) {
      callback(this.encodeError('Image URI must not be empty'));
      return;
    }
    const inputImage: detectBarcode.InputImage = { uri: imageURI };
    detectBarcode.decode(inputImage)
      .then((results: Array<scanBarcode.ScanResult>) => {
        if (results.length === 0) {
          callback(this.encodeOutcome(
            'noCodeFound', null, null, 'No code was found in the image'));
          return;
        }
        const first: scanBarcode.ScanResult = results[0];
        callback(this.encodeOutcome(
          'success', first.originalValue, this.formatName(first.scanType)));
      })
      .catch((error: BusinessError) => {
        callback(this.encodeError(
          this.errorMessage(error, 'Unable to decode the image')));
      });
  }

  private formatName(type: scanCore.ScanType): string {
    switch (type) {
      case scanCore.ScanType.QR_CODE:
        return 'qr_code';
      case scanCore.ScanType.AZTEC_CODE:
        return 'aztec';
      case scanCore.ScanType.CODABAR_CODE:
        return 'codabar';
      case scanCore.ScanType.CODE39_CODE:
        return 'code39';
      case scanCore.ScanType.CODE93_CODE:
        return 'code93';
      case scanCore.ScanType.CODE128_CODE:
        return 'code128';
      case scanCore.ScanType.DATAMATRIX_CODE:
        return 'data_matrix';
      case scanCore.ScanType.EAN8_CODE:
        return 'ean_8';
      case scanCore.ScanType.EAN13_CODE:
        return 'ean_13';
      case scanCore.ScanType.ITF14_CODE:
        return 'itf';
      case scanCore.ScanType.PDF417_CODE:
        return 'pdf417';
      case scanCore.ScanType.UPC_A_CODE:
        return 'upc_a';
      case scanCore.ScanType.UPC_E_CODE:
        return 'upc_e';
      case scanCore.ScanType.MULTIFUNCTIONAL_CODE:
        return 'multifunctional';
      default:
        return 'unknown';
    }
  }

  private encodeOutcome(
    code: string,
    content: string | null,
    format: string | null,
    message: string = '',
  ): string {
    return JSON.stringify(new ScanEnvelope(
      new ScanValue(code, content, format, message)));
  }

  private encodeError(message: string): string {
    return JSON.stringify(new ScanEnvelope(null, message));
  }

  private errorMessage(error: BusinessError, fallback: string): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
