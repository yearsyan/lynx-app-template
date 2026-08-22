import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { huks } from '@kit.UniversalKeystoreKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

interface NativePromptOptions {
  policy: string;
  title: string;
  reason: string;
  cancelButtonText: string | null;
}

interface NativeCreateKeyOptions {
  scope: string;
  attestationChallenge: string | null;
}

interface NativeKeyOptions {
  keyId: string;
}

interface NativeSignOptions {
  keyId: string;
  payload: string;
  title: string;
  reason: string;
  cancelButtonText: string | null;
}

class NativeBiometricSupport {
  policy: string;
  canAuthenticate: boolean;
  reason: string;
  biometryType: string;
  deviceCredentialSetup: boolean;

  constructor(
    policy: string,
    canAuthenticate: boolean,
    reason: string,
    biometryType: string,
    deviceCredentialSetup: boolean,
  ) {
    this.policy = policy;
    this.canAuthenticate = canAuthenticate;
    this.reason = reason;
    this.biometryType = biometryType;
    this.deviceCredentialSetup = deviceCredentialSetup;
  }
}

class NativeBiometricOutcome {
  code: string;
  message: string;
  policy: string;

  constructor(code: string, message: string, policy: string) {
    this.code = code;
    this.message = message;
    this.policy = policy;
  }
}

/** Common shape used by create/get/delete/sign crypto responses. */
class NativeBiometricCrypto {
  code: string;
  message: string;
  keyId: string | null;
  scope: string | null;
  publicKey: string | null;
  signature: string | null;
  securityLevel: string;
  attestationType: string;
  attestationCertificates: Array<string>;

  constructor(
    code: string,
    message: string,
    keyId: string | null,
    scope: string | null = null,
    publicKey: string | null = null,
    signature: string | null = null,
  ) {
    this.code = code;
    this.message = message;
    this.keyId = keyId;
    this.scope = scope;
    this.publicKey = publicKey;
    this.signature = signature;
    // HarmonyOS does not currently expose a stable hardware-level signal for
    // an exported HUKS key through this API surface.
    this.securityLevel = 'unknown';
    this.attestationType = 'none';
    this.attestationCertificates = [];
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

/**
 * HarmonyOS local authentication and HUKS-backed P-256 signing.
 *
 * Biometry type is informational. Authentication passes every enrolled type
 * that satisfies the requested trust level to the system, which chooses the
 * usable face/fingerprint sensor on devices that expose only one of them.
 */
export class BiometricModule extends LynxModule {
  static readonly NAME: string = 'Biometric';
  private static readonly KEY_ALIAS_PREFIX: string = 'lynx.biometric.signing.v2.';
  private static readonly SIGNING_DOMAIN: string = 'LYNX_BIOMETRIC_V2';

  private promptActive: boolean = false;
  private readonly base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  checkSupport(optionsJSON: string, callback: (resultJSON: string) => void): void {
    try {
      const policy: string = this.parsePolicyOptions(optionsJSON);
      callback(JSON.stringify(new NativeBiometricResult(this.readSupport(policy))));
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
    }
  }

  authenticate(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativePromptOptions;
    try {
      options = this.parsePromptOptions(optionsJSON);
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
      return;
    }
    if (this.promptActive) {
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricOutcome(
          'busy',
          'Another authentication request is already active',
          options.policy,
        ),
      )));
      return;
    }

    const trustLevel: userAuth.AuthTrustLevel = this.trustLevelForPolicy(options.policy);
    const authTypes: Array<userAuth.UserAuthType> = this.availableAuthTypes(
      trustLevel,
      options.policy === 'deviceOwnerAuthentication',
    );
    if (authTypes.length === 0) {
      const support: NativeBiometricSupport = this.readSupport(options.policy);
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricOutcome(
          this.outcomeCodeForSupport(support.reason),
          '',
          options.policy,
        ),
      )));
      return;
    }

    this.promptActive = true;
    try {
      const authParam: userAuth.AuthParam = {
        challenge: this.randomChallenge(),
        authType: authTypes,
        authTrustLevel: trustLevel,
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
          options.policy,
        ))));
      }));
      instance.start();
    } catch (error) {
      this.promptActive = false;
      callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricOutcome(
        'unavailable',
        errorMessage(error as Error),
        options.policy,
      ))));
    }
  }

  createSigningKey(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeCreateKeyOptions;
    try {
      options = this.parseCreateKeyOptions(optionsJSON);
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
      return;
    }
    const gate: string | null = this.cryptoGateCode();
    if (gate !== null) {
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricCrypto(gate, '', null),
      )));
      return;
    }

    const keyId: string = options.scope + '~' + util.generateRandomUUID(true).toLowerCase();
    const alias: string = BiometricModule.KEY_ALIAS_PREFIX + keyId;
    huks.generateKeyItem(alias, { properties: this.keygenProperties() })
      .then(() => huks.exportKeyItem(alias, { properties: [] }))
      .then((exported: huks.HuksReturnResult) => {
        const publicKey: string = this.publicKeyFromExport(exported);
        callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
          'success',
          '',
          keyId,
          options.scope,
          publicKey,
        ))));
      })
      .catch((error: BusinessError) => {
        // A failed export must not leave an unreferenced private key behind.
        huks.deleteKeyItem(alias, { properties: [] })
          .catch((_deleteError: BusinessError) => {})
          .then(() => {
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto('unknown', errorMessage(error), null),
            )));
          });
      });
  }

  getSigningKey(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeKeyOptions;
    try {
      options = this.parseKeyOptions(optionsJSON);
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
      return;
    }
    const alias: string = BiometricModule.KEY_ALIAS_PREFIX + options.keyId;
    huks.isKeyItemExist(alias, { properties: [] })
      .then((exists: boolean) => {
        if (!exists) {
          callback(JSON.stringify(new NativeBiometricResult(
            new NativeBiometricCrypto('keyNotFound', '', null),
          )));
          return;
        }
        huks.exportKeyItem(alias, { properties: [] })
          .then((exported: huks.HuksReturnResult) => {
            callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
              'success',
              '',
              options.keyId,
              this.scopeFromKeyId(options.keyId),
              this.publicKeyFromExport(exported),
            ))));
          })
          .catch((error: BusinessError) => {
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto(this.keyErrorCode(error), errorMessage(error), null),
            )));
          });
      })
      .catch((error: BusinessError) => {
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto(this.keyErrorCode(error), errorMessage(error), null),
        )));
      });
  }

  deleteSigningKey(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeKeyOptions;
    try {
      options = this.parseKeyOptions(optionsJSON);
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
      return;
    }
    if (this.promptActive) {
      callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
        'busy',
        'Another authentication request is already active',
        options.keyId,
      ))));
      return;
    }

    const alias: string = BiometricModule.KEY_ALIAS_PREFIX + options.keyId;
    this.promptActive = true;
    huks.isKeyItemExist(alias, { properties: [] })
      .then((exists: boolean) => {
        if (!exists) {
          this.promptActive = false;
          callback(JSON.stringify(new NativeBiometricResult(
            new NativeBiometricCrypto('keyNotFound', '', options.keyId),
          )));
          return;
        }
        huks.deleteKeyItem(alias, { properties: [] })
          .then(() => {
            this.promptActive = false;
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto('success', '', options.keyId),
            )));
          })
          .catch((error: BusinessError) => {
            this.promptActive = false;
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto(this.keyErrorCode(error), errorMessage(error), options.keyId),
            )));
          });
      })
      .catch((error: BusinessError) => {
        this.promptActive = false;
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto(this.keyErrorCode(error), errorMessage(error), options.keyId),
        )));
      });
  }

  signChallenge(optionsJSON: string, callback: (resultJSON: string) => void): void {
    let options: NativeSignOptions;
    let payload: Uint8Array;
    try {
      options = this.parseSignOptions(optionsJSON);
      payload = this.validateSigningPayload(options.payload, options.keyId);
    } catch (error) {
      callback(JSON.stringify(new NativeBiometricResult(null, errorMessage(error as Error))));
      return;
    }
    if (this.promptActive) {
      callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
        'busy',
        'Another authentication request is already active',
        options.keyId,
      ))));
      return;
    }
    const gate: string | null = this.cryptoGateCode();
    if (gate !== null) {
      callback(JSON.stringify(new NativeBiometricResult(
        new NativeBiometricCrypto(gate, '', options.keyId),
      )));
      return;
    }

    const alias: string = BiometricModule.KEY_ALIAS_PREFIX + options.keyId;
    const signOptions: huks.HuksOptions = {
      properties: this.signProperties(),
      inData: payload,
    };

    // Reserve the prompt before any asynchronous HUKS work, closing the race
    // in which two calls could both create a signing session.
    this.promptActive = true;
    huks.isKeyItemExist(alias, { properties: [] })
      .then((exists: boolean) => {
        if (!exists) {
          throw new Error('keyNotFound');
        }
        return huks.initSession(alias, signOptions);
      })
      .then((session: huks.HuksSessionHandle) => {
        const sessionChallenge: Uint8Array | undefined = session.challenge;
        if (sessionChallenge === undefined) {
          throw new Error('HUKS session produced no challenge');
        }
        const widgetParam: userAuth.WidgetParam = { title: options.title };
        if (options.cancelButtonText !== null) {
          widgetParam.navigationButtonText = options.cancelButtonText;
        }
        const instance = userAuth.getUserAuthInstance(
          {
            challenge: sessionChallenge,
            authType: [
              userAuth.UserAuthType.FINGERPRINT,
              userAuth.UserAuthType.FACE,
            ],
            // Signing keys always require strong biometry; policy is not
            // caller-selectable for this security-sensitive operation.
            authTrustLevel: userAuth.AuthTrustLevel.ATL3,
          },
          widgetParam,
        );
        instance.on('result', new NativeAuthCallback((result: userAuth.UserAuthResult) => {
          const fail = (code: string, message: string): void => {
            this.promptActive = false;
            huks.abortSession(session.handle, { properties: [] })
              .catch((_error: BusinessError) => {});
            callback(JSON.stringify(new NativeBiometricResult(
              new NativeBiometricCrypto(code, message, options.keyId),
            )));
          };
          if (result.result !== userAuth.UserAuthResultCode.SUCCESS) {
            fail(this.codeForResult(result.result), '');
            return;
          }
          const token: Uint8Array | undefined = result.token;
          if (token === undefined) {
            fail('unavailable', 'Authentication produced no token');
            return;
          }
          huks.finishSession(session.handle, signOptions, token)
            .then((finished: huks.HuksReturnResult) => {
              this.promptActive = false;
              const signature: Uint8Array | undefined = finished.outData;
              if (signature === undefined || signature.length < 8) {
                throw new Error('Empty signature');
              }
              callback(JSON.stringify(new NativeBiometricResult(new NativeBiometricCrypto(
                'success',
                '',
                options.keyId,
                null,
                null,
                this.base64.encodeToStringSync(this.ecdsaDerToRaw(signature)),
              ))));
            })
            .catch((error: BusinessError) => {
              this.promptActive = false;
              callback(JSON.stringify(new NativeBiometricResult(
                new NativeBiometricCrypto('unknown', errorMessage(error), options.keyId),
              )));
            });
        }));
        instance.start();
      })
      .catch((error: Error) => {
        this.promptActive = false;
        const code: string = error.message === 'keyNotFound'
          ? 'keyNotFound'
          : this.keyErrorCode(error as BusinessError);
        callback(JSON.stringify(new NativeBiometricResult(
          new NativeBiometricCrypto(code, error.message === 'keyNotFound' ? '' : errorMessage(error), options.keyId),
        )));
      });
  }

  private readSupport(policy: string): NativeBiometricSupport {
    const trustLevel: userAuth.AuthTrustLevel = this.trustLevelForPolicy(policy);
    const fingerprint: string = this.probeType(userAuth.UserAuthType.FINGERPRINT, trustLevel);
    const face: string = this.probeType(userAuth.UserAuthType.FACE, trustLevel);
    const pin: string = policy === 'deviceOwnerAuthentication'
      ? this.probeType(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL2)
      : 'unavailable';
    const deviceCredentialSetup: boolean =
      this.probeType(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL1) === 'ok';
    const biometryType: string = this.detectBiometryType(fingerprint, face);

    let reason: string = 'noHardware';
    if (fingerprint === 'ok' || face === 'ok' || pin === 'ok') {
      reason = 'ok';
    } else if (fingerprint === 'notEnrolled' || face === 'notEnrolled') {
      reason = 'notEnrolled';
    } else if (policy === 'deviceOwnerAuthentication' && !deviceCredentialSetup) {
      reason = 'noDeviceCredential';
    } else if (fingerprint === 'unavailable'
      || face === 'unavailable'
      || (policy === 'deviceOwnerAuthentication' && pin === 'unavailable')) {
      reason = 'unavailable';
    }
    return new NativeBiometricSupport(
      policy,
      reason === 'ok',
      reason,
      biometryType,
      deviceCredentialSetup,
    );
  }

  private detectBiometryType(fingerprint: string, face: string): string {
    if (fingerprint === 'ok') {
      return 'fingerprint';
    }
    if (face === 'ok') {
      return 'face';
    }
    // For a strong-policy probe, an enrolled weak sensor may report the trust
    // level as unavailable. Probe ATL2 only to preserve informational type.
    const weakFingerprint: string = this.probeType(
      userAuth.UserAuthType.FINGERPRINT,
      userAuth.AuthTrustLevel.ATL2,
    );
    const weakFace: string = this.probeType(
      userAuth.UserAuthType.FACE,
      userAuth.AuthTrustLevel.ATL2,
    );
    if (fingerprint === 'notEnrolled'
      || weakFingerprint === 'ok'
      || weakFingerprint === 'notEnrolled') {
      return 'fingerprint';
    }
    if (face === 'notEnrolled' || weakFace === 'ok' || weakFace === 'notEnrolled') {
      return 'face';
    }
    return 'unknown';
  }

  private availableAuthTypes(
    trustLevel: userAuth.AuthTrustLevel,
    includePin: boolean,
  ): Array<userAuth.UserAuthType> {
    const types: Array<userAuth.UserAuthType> = [];
    if (this.probeType(userAuth.UserAuthType.FINGERPRINT, trustLevel) === 'ok') {
      types.push(userAuth.UserAuthType.FINGERPRINT);
    }
    if (this.probeType(userAuth.UserAuthType.FACE, trustLevel) === 'ok') {
      types.push(userAuth.UserAuthType.FACE);
    }
    if (includePin
      && this.probeType(userAuth.UserAuthType.PIN, userAuth.AuthTrustLevel.ATL2) === 'ok') {
      types.push(userAuth.UserAuthType.PIN);
    }
    return types;
  }

  private probeType(
    type: userAuth.UserAuthType,
    trustLevel: userAuth.AuthTrustLevel,
  ): string {
    try {
      userAuth.getAvailableStatus(type, trustLevel);
      return 'ok';
    } catch (error) {
      const code: number = (error as BusinessError).code;
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

  private outcomeCodeForSupport(reason: string): string {
    if (reason === 'noHardware') {
      return 'noHardware';
    }
    if (reason === 'notEnrolled') {
      return 'notEnrolled';
    }
    if (reason === 'noDeviceCredential') {
      return 'noDeviceCredential';
    }
    if (reason === 'locked') {
      return 'locked';
    }
    return 'unavailable';
  }

  private cryptoGateCode(): string | null {
    const fingerprint: string = this.probeType(
      userAuth.UserAuthType.FINGERPRINT,
      userAuth.AuthTrustLevel.ATL3,
    );
    const face: string = this.probeType(
      userAuth.UserAuthType.FACE,
      userAuth.AuthTrustLevel.ATL3,
    );
    if (fingerprint === 'ok' || face === 'ok') {
      return null;
    }
    if (fingerprint === 'notEnrolled' || face === 'notEnrolled') {
      return 'notEnrolled';
    }
    return 'notSupported';
  }

  private trustLevelForPolicy(policy: string): userAuth.AuthTrustLevel {
    return policy === 'biometricStrong'
      ? userAuth.AuthTrustLevel.ATL3
      : userAuth.AuthTrustLevel.ATL2;
  }

  private parsePolicyOptions(optionsJSON: string): string {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    return this.requirePolicy(parsed['policy']);
  }

  private parsePromptOptions(optionsJSON: string): NativePromptOptions {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    return {
      policy: this.requirePolicy(parsed['policy']),
      title: this.requireText(parsed['title'], 'Biometric title', 200),
      reason: this.requireText(parsed['reason'], 'Biometric reason', 500),
      cancelButtonText: this.optionalText(
        parsed['cancelButtonText'],
        'Biometric cancelButtonText',
        60,
      ),
    };
  }

  private parseCreateKeyOptions(optionsJSON: string): NativeCreateKeyOptions {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    const scope: string = this.requireText(parsed['scope'], 'Biometric key scope', 64);
    if (!new RegExp('^[A-Za-z0-9._-]{1,64}$').test(scope)) {
      throw new Error(
        'Biometric key scope must be 1..64 ASCII letters, digits, dot, underscore, or hyphen',
      );
    }
    const attestationChallenge: string | null = this.optionalText(
      parsed['attestationChallenge'],
      'Biometric attestationChallenge',
      256,
    );
    if (attestationChallenge !== null) {
      const bytes: Uint8Array = this.decodeCanonicalBase64(
        attestationChallenge,
        'Biometric attestationChallenge',
      );
      if (bytes.length < 16 || bytes.length > 128) {
        throw new Error('Biometric attestationChallenge must decode to 16..128 bytes');
      }
    }
    return { scope: scope, attestationChallenge: attestationChallenge };
  }

  private parseKeyOptions(optionsJSON: string): NativeKeyOptions {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    const keyId: string = this.requireText(parsed['keyId'], 'Biometric keyId', 101);
    this.requireKeyId(keyId);
    return { keyId: keyId };
  }

  private parseSignOptions(optionsJSON: string): NativeSignOptions {
    const parsed = JSON.parse(optionsJSON) as Record<string, Object>;
    const keyId: string = this.requireText(parsed['keyId'], 'Biometric keyId', 101);
    this.requireKeyId(keyId);
    return {
      keyId: keyId,
      payload: this.requireText(parsed['payload'], 'Biometric signing payload', 300),
      title: this.requireText(parsed['title'], 'Biometric title', 200),
      reason: this.requireText(parsed['reason'], 'Biometric reason', 500),
      cancelButtonText: this.optionalText(
        parsed['cancelButtonText'],
        'Biometric cancelButtonText',
        60,
      ),
    };
  }

  private requirePolicy(value: Object | undefined): string {
    if (value === 'biometricWeak'
      || value === 'biometricStrong'
      || value === 'deviceOwnerAuthentication') {
      return value as string;
    }
    throw new Error('Biometric authentication policy is invalid');
  }

  private requireText(value: Object | undefined, label: string, maximum: number): string {
    if (typeof value !== 'string' || value.trim().length === 0) {
      throw new Error(label + ' must not be empty');
    }
    const normalized: string = value.trim();
    if (normalized.length > maximum) {
      throw new Error(label + ' is too long');
    }
    return normalized;
  }

  private optionalText(
    value: Object | undefined,
    label: string,
    maximum: number,
  ): string | null {
    if (value === undefined || value === null) {
      return null;
    }
    return this.requireText(value, label, maximum);
  }

  private requireKeyId(keyId: string): void {
    const pattern: RegExp = new RegExp(
      '^[A-Za-z0-9._-]{1,64}~[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (!pattern.test(keyId)) {
      throw new Error('Biometric keyId is invalid');
    }
  }

  private scopeFromKeyId(keyId: string): string {
    return keyId.substring(0, keyId.lastIndexOf('~'));
  }

  private validateSigningPayload(encoded: string, keyId: string): Uint8Array {
    const payload: Uint8Array = this.decodeCanonicalBase64(
      encoded,
      'Biometric signing payload',
    );
    const domain: Uint8Array = this.asciiBytes(BiometricModule.SIGNING_DOMAIN + '\0');
    const key: Uint8Array = this.asciiBytes(keyId);
    const prefixLength: number = domain.length + key.length + 1;
    const bodyLength: number = payload.length - prefixLength;
    if (bodyLength < 48 || bodyLength > 96) {
      throw new Error('Biometric signing payload has invalid bounds');
    }
    for (let i = 0; i < domain.length; i++) {
      if (payload[i] !== domain[i]) {
        throw new Error('Biometric signing payload has invalid domain');
      }
    }
    for (let i = 0; i < key.length; i++) {
      if (payload[domain.length + i] !== key[i]) {
        throw new Error('Biometric signing payload keyId mismatch');
      }
    }
    if (payload[domain.length + key.length] !== 0) {
      throw new Error('Biometric signing payload is malformed');
    }
    return payload;
  }

  private decodeCanonicalBase64(value: string, label: string): Uint8Array {
    const pattern: RegExp = new RegExp(
      '^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
    );
    if (value.length === 0 || value.length % 4 !== 0 || !pattern.test(value)) {
      throw new Error(label + ' must be non-empty standard Base64');
    }
    const bytes: Uint8Array = this.base64.decodeSync(value);
    if (this.base64.encodeToStringSync(bytes) !== value) {
      throw new Error(label + ' must use canonical standard Base64');
    }
    return bytes;
  }

  private asciiBytes(value: string): Uint8Array {
    const bytes: Uint8Array = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code > 0x7f) {
        throw new Error('Biometric protocol values must be ASCII');
      }
      bytes[i] = code;
    }
    return bytes;
  }

  private keygenProperties(): Array<huks.HuksParam> {
    return [
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
      {
        tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE,
        value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_INVALID_NEW_BIO_ENROLL,
      },
      {
        tag: huks.HuksTag.HUKS_TAG_CHALLENGE_TYPE,
        value: huks.HuksChallengeType.HUKS_CHALLENGE_TYPE_NORMAL,
      },
      {
        tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN,
      },
      {
        tag: huks.HuksTag.HUKS_TAG_USER_AUTH_MODE,
        value: huks.HuksUserAuthMode.HUKS_USER_AUTH_MODE_LOCAL,
      },
    ];
  }

  private signProperties(): Array<huks.HuksParam> {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ECC },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256 },
    ];
  }

  private publicKeyFromExport(exported: huks.HuksReturnResult): string {
    const exportedData: Uint8Array | undefined = exported.outData;
    if (exportedData === undefined || exportedData.length < 65) {
      throw new Error('Unable to export the public key');
    }
    const pointStart: number = exportedData.length - 65;
    if (exportedData[pointStart] !== 0x04) {
      throw new Error('Unexpected public key format');
    }
    return this.base64.encodeToStringSync(exportedData.slice(pointStart));
  }

  private keyErrorCode(error: BusinessError): string {
    return error.code === 12000011 ? 'keyNotFound' : 'unavailable';
  }

  /** Converts an ASN.1 DER ECDSA signature into the 64-byte r || s form. */
  private ecdsaDerToRaw(der: Uint8Array): Uint8Array {
    if (der.length < 8 || der[0] !== 0x30) {
      throw new Error('Malformed ECDSA signature');
    }
    let index: number = 2;
    if ((der[1] & 0x80) !== 0) {
      const lengthBytes: number = der[1] & 0x7f;
      if (lengthBytes < 1 || lengthBytes > 2 || 2 + lengthBytes >= der.length) {
        throw new Error('Malformed ECDSA signature');
      }
      index += lengthBytes;
    }
    const r: DerInteger = this.readDerInteger(der, index);
    const s: DerInteger = this.readDerInteger(der, r.next);
    if (s.next !== der.length) {
      throw new Error('Malformed ECDSA signature');
    }
    const raw: Uint8Array = new Uint8Array(64);
    copyPaddedBytes(r.bytes, raw, 0);
    copyPaddedBytes(s.bytes, raw, 32);
    return raw;
  }

  private readDerInteger(der: Uint8Array, offset: number): DerInteger {
    if (offset + 1 >= der.length || der[offset] !== 0x02) {
      throw new Error('Malformed ECDSA signature');
    }
    let length: number = der[offset + 1];
    let headerLength: number = 2;
    if ((length & 0x80) !== 0) {
      const lengthBytes: number = length & 0x7f;
      if (lengthBytes !== 1 || offset + 2 >= der.length) {
        throw new Error('Malformed ECDSA signature');
      }
      length = der[offset + 2];
      headerLength = 3;
    }
    let start: number = offset + headerLength;
    const end: number = start + length;
    if (length === 0 || end > der.length) {
      throw new Error('Malformed ECDSA signature');
    }
    while (start + 1 < end && der[start] === 0x00) {
      start += 1;
    }
    const bytes: Uint8Array = der.slice(start, end);
    if (bytes.length > 32) {
      throw new Error('Malformed ECDSA signature');
    }
    return new DerInteger(bytes, end);
  }

  private randomChallenge(): Uint8Array {
    const blob: cryptoFramework.DataBlob =
      cryptoFramework.createRandom().generateRandomSync(16);
    if (blob.data.length !== 16) {
      throw new Error('Unable to generate an authentication challenge');
    }
    return blob.data;
  }
}

/** IAuthCallback implementation that relays the terminal result only. */
class NativeAuthCallback implements userAuth.IAuthCallback {
  onResult: (result: userAuth.UserAuthResult) => void;

  constructor(onAuthResult: (result: userAuth.UserAuthResult) => void) {
    // Native userAuth invokes the callback function without preserving the
    // callback object's `this`, so keep the relay as an arrow closure.
    this.onResult = (result: userAuth.UserAuthResult): void => {
      onAuthResult(result);
    };
  }
}

/** Right-aligns a positive big-endian integer into exactly 32 bytes. */
function copyPaddedBytes(source: Uint8Array, target: Uint8Array, offset: number): void {
  const start: number = Math.max(0, source.length - 32);
  const count: number = source.length - start;
  const pad: number = 32 - count;
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
