import { sensor } from '@kit.SensorServiceKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class SensorEventPayload {
  type: string;
  x: number = 0;
  y: number = 0;
  z: number = 0;
  heading: number = 0;
  accuracy: number = -1;
  timestamp: number = 0;
  error: string = '';

  constructor(type: string) {
    this.type = type;
  }
}

/** Estimated azimuth uncertainty in degrees; -1 when the reading is unreliable. */
function accuracyDegrees(accuracy: sensor.SensorAccuracy): number {
  if (accuracy === sensor.SensorAccuracy.ACCURACY_HIGH) {
    return 15;
  }
  if (accuracy === sensor.SensorAccuracy.ACCURACY_MEDIUM) {
    return 30;
  }
  if (accuracy === sensor.SensorAccuracy.ACCURACY_LOW) {
    return 45;
  }
  return -1;
}

/** Page-owned sensor subscription hub exported to Lynx as Sensors. */
export class NativeSensorsController {
  private context: LynxContext | undefined;
  private destroyed: boolean = false;
  private accelerometerActive: boolean = false;
  private compassActive: boolean = false;

  isAvailable(type: string, callback: (resultJSON: string) => void): void {
    try {
      if (type === 'accelerometer') {
        sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      } else if (type === 'compass') {
        sensor.getSingleSensorSync(sensor.SensorId.ORIENTATION);
      } else {
        callback('{"error":"Unknown sensor type"}');
        return;
      }
      callback('{"value":true}');
    } catch (error) {
      callback('{"value":false}');
    }
  }

  start(type: string, callback: (error: string) => void, context: LynxContext): void {
    if (this.destroyed) {
      callback('Native sensors host has been destroyed');
      return;
    }
    this.context = context;
    if (type === 'accelerometer') {
      if (this.accelerometerActive) {
        callback('');
        return;
      }
      try {
        sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
          const payload: SensorEventPayload = new SensorEventPayload('accelerometer');
          payload.x = data.x;
          payload.y = data.y;
          payload.z = data.z;
          payload.timestamp = Date.now();
          this.emit(payload);
        });
        this.accelerometerActive = true;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to start the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      if (this.compassActive) {
        callback('');
        return;
      }
      try {
        sensor.on(sensor.SensorId.ORIENTATION, (data: sensor.OrientationResponse) => {
          const payload: SensorEventPayload = new SensorEventPayload('compass');
          // The orientation sensor fuses the magnetometer; alpha is the
          // azimuth relative to magnetic north in degrees.
          payload.heading = data.alpha;
          payload.accuracy = accuracyDegrees(data.accuracy);
          payload.timestamp = Date.now();
          this.emit(payload);
        });
        this.compassActive = true;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to start the compass'));
      }
      return;
    }
    callback('Unknown sensor type');
  }

  stop(type: string, callback: (error: string) => void): void {
    if (type === 'accelerometer') {
      if (!this.accelerometerActive) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER);
        this.accelerometerActive = false;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      if (!this.compassActive) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ORIENTATION);
        this.compassActive = false;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the compass'));
      }
      return;
    }
    callback('Unknown sensor type');
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
    } catch (_error) {
    }
    try {
      sensor.off(sensor.SensorId.ORIENTATION);
    } catch (_error) {
    }
    this.accelerometerActive = false;
    this.compassActive = false;
  }

  private emit(payload: SensorEventPayload): void {
    if (this.destroyed) {
      return;
    }
    this.context?.sendGlobalEvent(SensorsModule.EVENT_NAME, [payload]);
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }

}

/** HarmonyOS motion sensors exported to Lynx as Sensors. */
export class SensorsModule extends LynxModule {
  static readonly NAME: string = 'Sensors';
  static readonly EVENT_NAME: string = 'sensors';
  private readonly controller: NativeSensorsController | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.controller = param as NativeSensorsController | undefined;
  }

  isAvailable(type: string, callback: (resultJSON: string) => void): void {
    if (this.controller === undefined) {
      callback('{"value":false,"error":"Native sensors have no ArkUI page host"}');
      return;
    }
    this.controller.isAvailable(type, callback);
  }

  start(type: string, callback: (error: string) => void): void {
    if (this.controller === undefined) {
      callback('Native sensors have no ArkUI page host');
      return;
    }
    this.controller.start(type, callback, this.context);
  }

  stop(type: string, callback: (error: string) => void): void {
    if (this.controller === undefined) {
      callback('Native sensors have no ArkUI page host');
      return;
    }
    this.controller.stop(type, callback);
  }
}
