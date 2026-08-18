import { LynxContext, LynxModule } from '@lynx/lynx';
import { MMKV } from '@tencent/mmkv';

/** MMKV string primitives exported to Lynx as KV. */
export class KVModule extends LynxModule {
  static readonly NAME: string = 'KV';
  private readonly storage: MMKV;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.storage = MMKV.mmkvWithID('lynx.native.kv');
  }

  setString(key: string, value: string, callback: (error: string) => void): void {
    if (key.trim().length === 0 || !this.storage.encodeString(key, value)) {
      callback('Unable to persist MMKV key');
      return;
    }
    callback('');
  }

  getString(
    key: string,
    defaultValue: string | null,
    callback: (value: string | null) => void,
  ): void {
    const value = this.storage.decodeString(key, defaultValue ?? undefined);
    callback(value ?? defaultValue);
  }

  remove(key: string, callback: (error: string) => void): void {
    if (key.trim().length === 0) {
      callback('MMKV key must not be empty');
      return;
    }
    this.storage.removeValueForKey(key);
    callback('');
  }

  clear(callback: (error: string) => void): void {
    this.storage.clearAll();
    callback('');
  }

  contains(key: string, callback: (contains: boolean) => void): void {
    callback(key.trim().length > 0 && this.storage.containsKey(key));
  }
}
