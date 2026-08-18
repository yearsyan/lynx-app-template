import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { huks } from '@kit.UniversalKeystoreKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

interface NativeBiometricOptions {
  title: string;
  reason: string;
  cancelButtonText: string | null;
  allowDeviceCredential: boolean;
  challenge: string | null;
}

class NativeBiometricSupport {
  canAuthenticate: boolean;
  reason: string;
  biometryType: string;
  deviceCredentialSetup: boolean;

  constructor(
    canAuthenticate: boolean,
    reason: string,
    biometryType: string,
    deviceCredentialSetup: boolean,
  ) {
    this.canAuthenticate = canAuthenticate;
    this.reason = reason;
    this.biometryType = biometryType;
    this.deviceCredentialSetup = deviceCredentialSetup;
  }
}

class NativeBiometricOutcome {
  code: string;
  message: string;

  constructor(code: string, message: string) {
    this.code = code;
    this.message = message;
  }
}

/** Payload of the createSigningKey / signChallenge crypto envelope. */
class NativeBiometricCrypto {
  code: string;
  message: string;
  publicKey: string | null;
  signature: string | null;

  constructor(code: string, message: string, field: string, payload: string | null) {
    this.code = code;
    this.message = message;
    this.publicKey = field === 'publicKey' ? payload : null;
    this.signature = field === 'signature' ? payload : null;
  }
}

class NativeBiometricResult {
  value: NativeBiometricSupport | NativeBiometricOutcome | NativeBiometricCrypto | null;
  error: string;

  constructor(
    value: NativeBiometricSupport | NativeBiometricOutcome | NativeBiometricCrypto | null,
    error: string = '',
  ) {
    this.value = value;
    this.error = error;
  }
}

/** One INTEGER read out of an ASN.1 DER ECDSA signature. */
class DerInteger {
  bytes: Uint8Array;
  next: number;

  constructor(bytes: Uint8Array, next: number) {
    this.bytes = bytes;
    this.next = next;
  }
}

/** Single probe result of one userAuth.getAvailableStatus call: 'ok',
 * 'notEnrolled', 'noHardware' or 'unavailable'. */

/**
 * HarmonyOS biometric authentication exported to Lynx as Biometric.
 * Capability checks use getAvailableStatus; authentication shows the
 * system userAuth widget through getUserAuthInstance.
 */
export class BiometricModule extends LynxModule {
  static readonly NAME: string = 'Biometric';
  /** Fixed HUKS alias of the app's biometric-gated signing key. */
  private static readonly KEY_ALIAS: string = 'lynx.biometric.signing';

  private promptActive: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  checkSupport(callback: (resultJSON: string) => void): void {
    try {
      const support = this.readSupport();
      callback(JSON.stringify(new NativeBiometricResult(support)));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new NativeBiometricResult(null, message)));
    }
  }

  authenticate(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeBiometricOptions;
    try {
      options = this.parseOptions(optionsJSON);
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new NativeBiometricResult(null, message)));
      return;
    }
    if (this.promptActive) {
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricOutcome('busy', 'Another authentication request is already active'),
      )));
      return;
    }

    try {
      const authTypes: userAuth.UserAuthType[] = [
        userAuth.UserAuthType.FINGERPRINT,
        userAuth.UserAuthType.FACE,
      ];
      if (options.allowDeviceCredential) {
        authTypes.push(userAuth.UserAuthType.PIN);
      }
      const authParam: userAuth.AuthParam = {
        // The challenge only drives the system session; it is not verified
        // against anything, so entropy beyond Math.random is unnecessary.
        challenge: this.randomChallenge(),
        authType: authTypes,
        authTrustLevel: userAuth.AuthTrustLevel.ATL2,
      };
      const widgetParam: userAuth.WidgetParam = { title: options.title };
      if (options.cancelButtonText !== null) {
        widgetParam.navigationButtonText = options.cancelButtonText;
      }
      const instance = userAuth.getUserAuthInstance(authParam, widgetParam);
      instance.on('result', new NativeAuthCallback((result: userAuth.UserAuthResult) => {
        this.promptActive = false;
        callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricOutcome(
          this.codeForResult(result.result),
          '',
        ))));
      }));
      this.promptActive = true;
      instance.start();
    } catch (error) {
      this.promptActive = false;
      const businessError = error as BusinessError;
      const message = businessError.message !== undefined
        && businessError.message.length > 0
        ? businessError.message
        : 'Unable to start biometric authentication';
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricOutcome('unavailable', message),
      )));
    }
  }

  private readSupport(): NativeBiometricSupport {
    const fingerprint = this.probeType(userAuth.UserAuthType.FINGERPRINT);
    const face = this.probeType(userAuth.UserAuthType.FACE);
    // A PIN probe at ATL1 succeeds exactly when a lock-screen credential
    // (PIN / password / pattern) is enrolled.
    const deviceCredentialSetup =
      this.probeType(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL1) === 'ok';

    let biometryType = 'unknown';
    let reason = 'noHardware';
    if (fingerprint === 'ok') {
      biometryType = 'fingerprint';
      reason = 'ok';
    } else if (face === 'ok') {
      biometryType = 'face';
      reason = 'ok';
    } else if (fingerprint === 'notEnrolled' || face === 'notEnrolled') {
      biometryType = fingerprint !== 'noHardware' ? 'fingerprint' : 'face';
      reason = 'notEnrolled';
    } else if (fingerprint === 'unavailable' || face === 'unavailable') {
      reason = 'unavailable';
    }
    return new NativeBiometricSupport(
      reason === 'ok',
      reason,
      biometryType,
      deviceCredentialSetup,
    );
  }

  private probeType(
    type: userAuth.UserAuthType,
    trustLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL2,
  ): string {
    try {
      userAuth.getAvailableStatus(type, trustLevel);
      return 'ok';
    } catch (error) {
      const code = (error as BusinessError).code;
      if (code === 12500010) {
        return 'notEnrolled';
      }
      if (code === 12500005) {
        return 'noHardware';
      }
      return 'unavailable';
    }
  }

  private codeForResult(result: number): string {
    switch (result) {
      case userAuth.UserAuthResultCode.SUCCESS:
        return 'success';
      case userAuth.UserAuthResultCode.CANCELED:
      case userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET:
        return 'userCancel';
      case userAuth.UserAuthResultCode.NOT_ENROLLED:
        return 'notEnrolled';
      case userAuth.UserAuthResultCode.LOCKED:
        return 'locked';
      case userAuth.UserAuthResultCode.PIN_EXPIRED:
        return 'noDeviceCredential';
      case userAuth.UserAuthResultCode.TIMEOUT:
        return 'timeout';
      case userAuth.UserAuthResultCode.BUSY:
        return 'busy';
      case userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT:
      case userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT:
        return 'unavailable';
      case userAuth.UserAuthResultCode.FAIL:
        return 'failed';
      default:
        return 'unknown';
    }
  }

  createSigningKey(callback: (resultJSON: string) => void): void {
    const gate = this.cryptoGateCode();
    if (gate !== null) {
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricCrypto(gate, '', 'publicKey', null),
      )));
      return;
    }
    // The private key is bound to biometric authentication and never leaves
    // HUKS; finishSession only succeeds with a fresh auth token.
    const keygenProperties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ECC },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN
          | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_VERIFY,
      },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256 },
      {
        tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
        value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT
          | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE,
      },
    ];
    // createSigningKey replaces any previous key on purpose: the server
    // rebinds to the returned public key anyway.
    huks.deleteKeyItem(BiometricModule.KEY_ALIAS, { properties: [] })
      .catch((_error: BusinessError) => {})
      .then(() =>
        huks.generateKeyItem(BiometricModule.KEY_ALIAS, { properties: keygenProperties }))
      .then(() => huks.exportKeyItem(BiometricModule.KEY_ALIAS, { properties: [] }))
      .then((exported: huks.HuksReturnResult) => {
        const exportedData = exported.outData;
        if (exportedData === undefined || exportedData.length < 65) {
          throw new Error('Unable to export the public key');
        }
        const pointStart = exportedData.length - 65;
        if (exportedData[pointStart] !== 0x04) {
          throw new Error('Unexpected public key format');
        }
        const publicKey = new util.Base64Helper()
          .encodeToStringSync(exportedData.slice(pointStart));
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto('success', '', 'publicKey', publicKey),
        )));
      })
      .catch((error: BusinessError) => {
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto('unknown', errorMessage(error), 'publicKey', null),
        )));
      });
  }

  signChallenge(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeBiometricOptions;
    try {
      options = this.parseOptions(optionsJSON);
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new NativeBiometricResult(null, message)));
      return;
    }
    if (options.challenge === null || options.challenge.length === 0) {
      callback(JSON.stringify(new NativeBiometricResult(null, 'Biometric challenge must not be empty')));
      return;
    }
    if (this.promptActive) {
      callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
        'busy', 'Another authentication request is already active', 'signature', null,
      ))));
      return;
    }
    const base64 = new util.Base64Helper();
    const challengeBytes: Uint8Array = base64.decodeSync(options.challenge);
    if (challengeBytes.length === 0) {
      callback(JSON.stringify(new NativeBiometricResult(null, 'Biometric challenge must not be empty')));
      return;
    }

    const signProperties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256 },
    ];
    huks.initSession(BiometricModule.KEY_ALIAS, { properties: signProperties })
      .then((session: huks.HuksSessionHandle) => {
        const sessionChallenge = session.challenge;
        if (sessionChallenge === undefined) {
          throw new Error('HUKS session produced no challenge');
        }
        this.promptActive = true;
        const widgetParam: userAuth.WidgetParam = { title: options.title };
        if (options.cancelButtonText !== null) {
          widgetParam.navigationButtonText = options.cancelButtonText;
        }
        const instance = userAuth.getUserAuthInstance(
          {
            // The HUKS session challenge binds the auth token to this exact
            // signing operation, preventing token replay.
            challenge: sessionChallenge,
            authType: [
              userAuth.UserAuthType.FINGERPRINT,
              userAuth.UserAuthType.FACE,
            ],
            authTrustLevel: userAuth.AuthTrustLevel.ATL2,
          },
          widgetParam,
        );
        instance.on('result', new NativeAuthCallback((result: userAuth.UserAuthResult) => {
          const fail = (code: string, message: string): void => {
            this.promptActive = false;
            huks.abortSession(session.handle, { properties: [] })
              .catch((_error: BusinessError) => {});
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto(code, message, 'signature', null),
            )));
          };
          if (result.result !== userAuth.UserAuthResultCode.SUCCESS) {
            fail(this.codeForResult(result.result), '');
            return;
          }
          const token = result.token;
          if (token === undefined) {
            fail('unavailable', 'Authentication produced no token');
            return;
          }
          huks.finishSession(
            session.handle,
            {
              properties: [
                { tag: huks.HuksTag.HUKS_TAG_AUTH_TOKEN, value: token },
              ],
            },
            challengeBytes,
          ).then((finished: huks.HuksReturnResult) => {
            this.promptActive = false;
            const signature = finished.outData;
            if (signature === undefined || signature.length < 8) {
              throw new Error('Empty signature');
            }
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto(
                'success',
                '',
                'signature',
                base64.encodeToStringSync(this.ecdsaDerToRaw(signature)),
              ),
            )));
          }).catch((error: BusinessError) => {
            this.promptActive = false;
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto('unknown', errorMessage(error), 'signature', null),
            )));
          });
        }));
        instance.start();
      })
      .catch((error: BusinessError) => {
        this.promptActive = false;
        const code = error.code === 12000011 ? 'keyNotFound' : 'unavailable';
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto(code, errorMessage(error), 'signature', null),
        )));
      });
  }

  private cryptoGateCode(): string | null {
    const fingerprint = this.probeType(userAuth.UserAuthType.FINGERPRINT);
    if (fingerprint === 'ok') {
      return null;
    }
    if (this.probeType(userAuth.UserAuthType.FACE) === 'ok') {
      return null;
    }
    if (fingerprint === 'notEnrolled'
      || this.probeType(userAuth.UserAuthType.FACE) === 'notEnrolled') {
      return 'notEnrolled';
    }
    return 'notSupported';
  }

  /** Converts an ASN.1 DER ECDSA signature into the 64-byte r || s form. */
  private ecdsaDerToRaw(der: Uint8Array): Uint8Array {
    if (der.length < 8 || der[0] !== 0x30) {
      throw new Error('Malformed ECDSA signature');
    }
    let index = (der[1] & 0x80) === 0 ? 2 : 2 + (der[1] & 0x7f);
    const r = this.readDerInteger(der, index);
    const s = this.readDerInteger(der, r.next);
    const raw = new Uint8Array(64);
    copyPaddedBytes(r.bytes, raw, 0);
    copyPaddedBytes(s.bytes, raw, 32);
    return raw;
  }

  private readDerInteger(der: Uint8Array, offset: number): DerInteger {
    if (offset + 1 >= der.length || der[offset] !== 0x02) {
      throw new Error('Malformed ECDSA signature');
    }
    const length = der[offset + 1];
    let start = offset + 2;
    let count = length;
    if (count > 1 && der[start] === 0x00 && (der[start + 1] & 0x80) !== 0) {
      start += 1;
      count -= 1;
    }
    while (count > 0 && der[start] === 0x00) {
      start += 1;
      count -= 1;
    }
    return new DerInteger(der.slice(start, start + count), offset + 2 + length);
  }

  private parseOptions(optionsJSON: string): NativeBiometricOptions {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    const title = parsed['title'];
    const reason = parsed['reason'];
    if (typeof title !== 'string' || title.trim().length === 0) {
      throw new Error('Biometric title must not be empty');
    }
    if (typeof reason !== 'string' || reason.trim().length === 0) {
      throw new Error('Biometric reason must not be empty');
    }
    let cancelButtonText: string | null = null;
    const rawCancel = parsed['cancelButtonText'];
    if (typeof rawCancel === 'string' && rawCancel.trim().length > 0) {
      cancelButtonText = rawCancel.trim();
    }
    let challenge: string | null = null;
    const rawChallenge = parsed['challenge'];
    if (typeof rawChallenge === 'string' && rawChallenge.trim().length > 0) {
      challenge = rawChallenge.trim();
    }
    const allowDeviceCredential = parsed['allowDeviceCredential'] === true;
    return {
      title: title.trim(),
      reason: reason.trim(),
      cancelButtonText: cancelButtonText,
      allowDeviceCredential: allowDeviceCredential,
      challenge: challenge,
    };
  }

  private randomChallenge(): Uint8Array {
    const bytes = new Uint8Array(16);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return bytes;
  }
}

/** IAuthCallback implementation that relays the terminal result only. */
class NativeAuthCallback implements userAuth.IAuthCallback {
  private onAuthResult: (result: userAuth.UserAuthResult) => void;

  constructor(onAuthResult: (result: userAuth.UserAuthResult) => void) {
    this.onAuthResult = onAuthResult;
  }

  onResult(result: userAuth.UserAuthResult): void {
    this.onAuthResult(result);
  }
}

/** Right-aligns a positive big-endian integer into exactly 32 bytes. */
function copyPaddedBytes(source: Uint8Array, target: Uint8Array, offset: number): void {
  const start = Math.max(0, source.length - 32);
  const count = source.length - start;
  const pad = 32 - count;
  for (let i = 0; i < pad; i++) {
    target[offset + i] = 0;
  }
  for (let i = 0; i < count; i++) {
    target[offset + pad + i] = source[start + i];
  }
}

function errorMessage(error: Error): string {
  return error.message.length > 0 ? error.message : JSON.stringify(error);
}
