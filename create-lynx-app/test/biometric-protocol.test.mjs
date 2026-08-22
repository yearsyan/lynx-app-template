import assert from 'node:assert/strict';
import { generateKeyPairSync, sign, verify } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const repositoryDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

async function loadProtocol() {
  const source = await readFile(
    resolve(repositoryDirectory, 'autolink/biometric/src/protocol.ts'),
    'utf8',
  );
  const transpiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.ES2022,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'protocol.ts',
    reportDiagnostics: true,
  });
  assert.deepEqual(transpiled.diagnostics, []);
  return import(
    `data:text/javascript;base64,${Buffer.from(transpiled.outputText).toString('base64')}`
  );
}

const protocol = await loadProtocol();
const keyId = 'payments~123e4567-e89b-42d3-a456-426614174000';

test('biometric v2 signing payload has a stable domain-separated layout', () => {
  const contextHash = Buffer.from(Array.from({ length: 32 }, (_, i) => i));
  const challenge = Buffer.from(Array.from({ length: 16 }, (_, i) => 0xa0 + i));
  const encoded = protocol.buildBiometricSigningPayload({
    keyId,
    contextHash: contextHash.toString('base64'),
    challenge: challenge.toString('base64'),
  });
  const expected = Buffer.concat([
    Buffer.from('LYNX_BIOMETRIC_V2\0', 'ascii'),
    Buffer.from(keyId, 'ascii'),
    Buffer.from([0]),
    contextHash,
    challenge,
  ]);

  assert.equal(protocol.BIOMETRIC_V2_SIGNING_DOMAIN, 'LYNX_BIOMETRIC_V2');
  assert.deepEqual(Buffer.from(encoded, 'base64'), expected);
});

test('biometric v2 payload verifies as ES256 with P1363 encoding', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  const payload = Buffer.from(
    protocol.buildBiometricSigningPayload({
      keyId,
      contextHash: Buffer.alloc(32, 0x5a).toString('base64'),
      challenge: Buffer.alloc(32, 0xc3).toString('base64'),
    }),
    'base64',
  );
  const signature = sign('sha256', payload, {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });

  assert.equal(signature.length, 64);
  assert.equal(
    verify(
      'sha256',
      payload,
      { key: publicKey, dsaEncoding: 'ieee-p1363' },
      signature,
    ),
    true,
  );
});

test('biometric v2 rejects malformed identifiers and non-canonical inputs', () => {
  assert.equal(protocol.isBiometricKeyId(keyId), true);
  assert.equal(protocol.biometricScopeFromKeyId(keyId), 'payments');
  assert.equal(protocol.normalizeBiometricScope('  account_1  '), 'account_1');
  assert.throws(() => protocol.normalizeBiometricScope('account/user'));
  assert.throws(() => protocol.requireBiometricKeyId('payments'));
  assert.throws(() => protocol.decodeStandardBase64('Zh==', 'value'));
  assert.throws(() =>
    protocol.buildBiometricSigningPayload({
      keyId,
      contextHash: Buffer.alloc(31).toString('base64'),
      challenge: Buffer.alloc(16).toString('base64'),
    }),
  );
  assert.throws(() =>
    protocol.buildBiometricSigningPayload({
      keyId,
      contextHash: Buffer.alloc(32).toString('base64'),
      challenge: Buffer.alloc(15).toString('base64'),
    }),
  );
});
