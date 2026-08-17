import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { MMKV } from '@tencent/mmkv';
import { LynxContext, LynxModule } from '@lynx/lynx';

/** One sealed secret: the GCM nonce and the ciphertext halves. */
class SealedValue {
  nonce: Uint8Array;
  cipher: Uint8Array;

  constructor(nonce: Uint8Array, cipher: Uint8Array) {
    this.nonce = nonce;
    this.cipher = cipher;
  }
}

/**
 * Small-secret string storage exported to Lynx as SecureStorage. Values are
 * sealed with an AES-256-GCM key held inside HUKS; only the base64 IV and
 * ciphertext are persisted in a dedicated MMKV instance.
 */
export class SecureStorageModule extends LynxModule {
  static readonly NAME: string = 'SecureStorage';
  /** Fixed HUKS alias of the app's symmetric storage key. */
  private static readonly KEY_ALIAS: string = 'lynx.secure.storage.key';
  private static readonly IV_BYTES: number = 12;
  /** Keeps the store to small secrets; mirrored by the shared TS facade. */
  private static readonly MAX_VALUE_LENGTH: number = 64 * 1024;

  private readonly storage: MMKV;
  private readonly base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.storage = MMKV.mmkvWithID('lynx.secure.storage');
  }

  setString(key: string, value: string, callback: (error: string) => void): void {
    if (!SecureStorageModule.isValidKey(key)) {
      callback('Secure storage key must not be empty');
      return;
    }
    if (value === undefined || value === null
      || value.length > SecureStorageModule.MAX_VALUE_LENGTH) {
      callback('Secure storage value is missing or too large');
      return;
    }
    this.ensureKey()
      .then(() => this.encrypt(new util.TextEncoder().encodeInto(value)))
      .then((sealed: SealedValue) => {
        const entry: string =
          `${this.base64.encodeToStringSync(sealed.nonce)}:${this.base64.encodeToStringSync(sealed.cipher)}`;
        if (!this.storage.encodeString(key, entry)) {
          callback('Unable to persist the secure value');
          return;
        }
        callback('');
      })
      .catch((error: BusinessError) => {
        callback(SecureStorageModule.errorMessage(error, 'Unable to write the secure value'));
      });
  }

  getString(
    key: string,
    defaultValue: string | null,
    callback: (value: string | null) => void,
  ): void {
    if (!SecureStorageModule.isValidKey(key)) {
      callback(defaultValue);
      return;
    }
    const entry: string | undefined = this.storage.decodeString(key, undefined);
    if (entry === undefined || entry === null) {
      callback(defaultValue);
      return;
    }
    this.decrypt(this.parseEntry(entry))
      .then((plain: Uint8Array) => {
        callback(util.TextDecoder.create('utf-8').decodeToString(plain));
      })
      .catch((_error: BusinessError) => {
        // GCM verification fails when the entry was tampered with or the
        // HUKS key was wiped; both behave like missing data.
        callback(defaultValue);
      });
  }

  remove(key: string, callback: (error: string) => void): void {
    if (!SecureStorageModule.isValidKey(key)) {
      callback('Secure storage key must not be empty');
      return;
    }
    this.storage.removeValueForKey(key);
    callback('');
  }

  private ensureKey(): Promise<void> {
    return huks.isKeyItemExist(SecureStorageModule.KEY_ALIAS, { properties: [] })
      .catch((_error: BusinessError) => false)
      .then((exists: boolean) => {
        if (exists) {
          return null;
        }
        return huks.generateKeyItem(SecureStorageModule.KEY_ALIAS, {
          properties: SecureStorageModule.keygenProperties(),
        });
      })
      .then(() => {});
  }

  private encrypt(plain: Uint8Array): Promise<SealedValue> {
    return this.randomBytes(SecureStorageModule.IV_BYTES)
      .then((nonce: Uint8Array) => {
        const properties: Array<huks.HuksParam> = [
          { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
          { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
          { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
          { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
        ];
        return huks.initSession(SecureStorageModule.KEY_ALIAS, { properties: properties })
          .then((session: huks.HuksSessionHandle) =>
            huks.finishSession(session.handle, { properties: properties }, plain))
          .then((result: huks.HuksReturnResult) => {
            if (result.outData === undefined || result.outData.length === 0) {
              throw new Error('HUKS encryption produced no data');
            }
            return new SealedValue(nonce, result.outData);
          });
      });
  }

  private decrypt(sealed: SealedValue): Promise<Uint8Array> {
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: sealed.nonce },
    ];
    return huks.initSession(SecureStorageModule.KEY_ALIAS, { properties: properties })
      .then((session: huks.HuksSessionHandle) =>
        huks.finishSession(session.handle, { properties: properties }, sealed.cipher))
      .then((result: huks.HuksReturnResult) => {
        if (result.outData === undefined) {
          throw new Error('HUKS decryption produced no data');
        }
        return result.outData;
      });
  }

  private randomBytes(length: number): Promise<Uint8Array> {
    const blob: cryptoFramework.DataBlob =
      cryptoFramework.createRandom().generateRandomSync(length);
    if (blob.data.length !== length) {
      return Promise.reject(new Error('Unable to generate a random IV'));
    }
    return Promise.resolve(blob.data);
  }

  private parseEntry(entry: string): SealedValue {
    const separator: number = entry.indexOf(':');
    if (separator <= 0 || separator + 1 >= entry.length) {
      throw new Error('Malformed secure entry');
    }
    const nonce: Uint8Array = this.base64.decodeSync(entry.substring(0, separator));
    const cipher: Uint8Array = this.base64.decodeSync(entry.substring(separator + 1));
    if (nonce.length !== SecureStorageModule.IV_BYTES || cipher.length === 0) {
      throw new Error('Malformed secure entry');
    }
    return new SealedValue(nonce, cipher);
  }

  private static keygenProperties(): Array<huks.HuksParam> {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT
          | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    ];
  }

  private static isValidKey(key: string): boolean {
    return key !== undefined && key !== null && key.trim().length > 0;
  }

  private static errorMessage(error: Error, fallback: string): string {
    const message: string = error instanceof Error
      ? error.message
      : JSON.stringify(error);
    return message.length > 0 ? message : fallback;
  }
}
