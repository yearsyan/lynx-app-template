# @lynx-template/autolink-storage

Autolinked string storage for Lynx hosts (Android, iOS & HarmonyOS). Exports
one Lynx NativeModule, `Storage`, with two backends:

| Method | JS facade | Backend |
| --- | --- | --- |
| `setString(key, value, cb, inMemory)` | `kv.setString` | shared MMKV (`lynx.native.kv`) or the in-memory overlay |
| `getString(key, defaultValue, cb)` / `getStringOrNull(key, cb)` | `kv.getString` | overlay first, then shared MMKV |
| `remove(key, cb)` | `kv.remove` | shared MMKV |
| `clear(cb)` | `kv.clear` | shared MMKV |
| `contains(key, cb)` | `kv.contains` | shared MMKV |
| `secureSetString(key, value, cb)` | `secureStorage.setString` | encrypted small-secret store |
| `secureGetString(key, defaultValue, cb)` / `secureGetStringOrNull(key, cb)` | `secureStorage.getString` | encrypted small-secret store |
| `secureRemove(key, cb)` | `secureStorage.remove` | encrypted small-secret store |

The secure methods carry the `secure` prefix because both stores expose the
same string primitive shapes over one module.

Notes:

- `kv` is the plain store every bundle may share; JSON encoding stays in
  TypeScript (`kv.setJSON` / `kv.getJSON`).
- `kv.setString(key, value, true)` writes only a process-wide native
  dictionary: the MMKV copy is left untouched, so reads return the overlay
  value until the process dies. A later persisted write
  (`kv.setString(key, value)` / `inMemory: false`) drops the overlay entry
  and makes MMKV authoritative again. Reads, `remove`, `clear` and
  `contains` all check the overlay before MMKV, so the overlay shadows —
  but never corrupts — persisted data.
- `secureStorage` is for small secrets (tokens, session payloads) only:
  values are limited to 64 KiB and are sealed with an AES-256-GCM key that
  never leaves the platform secure element — Android Keystore, iOS
  Keychain (device-only generic passwords) and HarmonyOS HUKS. Tampered
  entries or wiped keys behave like missing data (default value).
- The library owns its MMKV bootstrap (idempotent per process), so hosts
  never call `MMKV.initialize()` themselves. All platforms use MMKV ID
  `lynx.native.kv`; secure entries live in a separate instance/area.
