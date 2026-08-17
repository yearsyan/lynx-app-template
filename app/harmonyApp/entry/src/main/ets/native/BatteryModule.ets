import { batteryInfo } from '@kit.BasicServicesKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class BatteryValue {
  level: number | null;
  charging: boolean;

  constructor() {
    if (batteryInfo.isBatteryPresent) {
      const soc: number = batteryInfo.batterySOC;
      this.level = soc >= 0 && soc <= 100 ? soc / 100 : null;
    } else {
      this.level = null;
    }
    const status: batteryInfo.BatteryChargeState = batteryInfo.chargingStatus;
    this.charging = status === batteryInfo.BatteryChargeState.ENABLE ||
      status === batteryInfo.BatteryChargeState.FULL;
  }
}

class BatteryResult {
  value: BatteryValue | null;
  error: string;

  constructor(value: BatteryValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/** On-demand battery state exported to Lynx as Battery. */
export class BatteryModule extends LynxModule {
  static readonly NAME: string = 'Battery';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  getInfo(callback: (resultJSON: string) => void): void {
    try {
      callback(JSON.stringify(new BatteryResult(new BatteryValue())));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new BatteryResult(null, message)));
    }
  }
}
