# autolink/network-info

The `NetworkInfo` NativeModule: current network reachability
(`networkInfo.getInfo()`) and change observation (`networkInfo.observe()`),
with the same snapshot shape on Android, iOS and HarmonyOS.

```ts
import { networkInfo } from '@lynx-template/autolink-network-info';

const snapshot = await networkInfo.getInfo();
// { connected: true, type: 'wifi', cellularGeneration: null, timestamp: … }

const stop = networkInfo.observe((next) => {
  'background only';
  console.info(`network: ${next.type} connected=${next.connected}`);
});
// stop() unsubscribes; the last unsubscribe tears down the native listener.
```

- `type` is one of `'wifi' | 'cellular' | 'ethernet' | 'other' | 'none' | 'unknown'`.
- `cellularGeneration` (`'2g' | '3g' | '4g' | '5g' | null`) is best-effort:
  Android reports it only when the host holds `READ_PHONE_STATE` (this
  template does not), iOS only on devices with a modem, HarmonyOS never.
- The first observer registers the native listener and immediately receives
  the current snapshot; the last unsubscribe removes it.

Platform sources:

- Android: `ConnectivityManager` active network + `registerDefaultNetworkCallback`
  (`ACCESS_NETWORK_STATE`, declared in this library's manifest and merged
  into the host).
- iOS: `NWPathMonitor` + `CTTelephonyNetworkInfo` (no permission needed).
- HarmonyOS: `@kit.NetworkKit` `connection` (`GET_NETWORK_INFO`, declared by
  the host entry module).
