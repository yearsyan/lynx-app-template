import { sensor } from '@kit.SensorServiceKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';

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

/** Owns the subscriptions created by one Lynx NativeModule instance. */
class NativeSensorsController {
  private context: LynxContext | undefined = undefined;
  private destroyed: boolean = false;
  private accelerometerCallback: ((data: sensor.AccelerometerResponse) => void) | undefined = undefined;
  private compassCallback: ((data: sensor.OrientationResponse) => void) | undefined = undefined;

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
    this.destroyed = false;
    this.context = context;
    if (type === 'accelerometer') {
      if (this.accelerometerCallback !== undefined) {
        callback('');
        return;
      }
      try {
        const listener = (data: sensor.AccelerometerResponse): void => {
          const payload = new SensorEventPayload('accelerometer');
          payload.x = data.x;
          payload.y = data.y;
          payload.z = data.z;
          payload.timestamp = Date.now();
          this.emit(payload);
        };
        sensor.on(sensor.SensorId.ACCELEROMETER, listener);
        this.accelerometerCallback = listener;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to start the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      if (this.compassCallback !== undefined) {
        callback('');
        return;
      }
      try {
        const listener = (data: sensor.OrientationResponse): void => {
          const payload = new SensorEventPayload('compass');
          payload.heading = data.alpha;
          payload.accuracy = accuracyDegrees(data.accuracy);
          payload.timestamp = Date.now();
          this.emit(payload);
        };
        sensor.on(sensor.SensorId.ORIENTATION, listener);
        this.compassCallback = listener;
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
      const listener = this.accelerometerCallback;
      if (listener === undefined) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER, listener);
        this.accelerometerCallback = undefined;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      const listener = this.compassCallback;
      if (listener === undefined) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ORIENTATION, listener);
        this.compassCallback = undefined;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the compass'));
      }
      return;
    }
    callback('Unknown sensor type');
  }

  destroy(): void {
    this.destroyed = true;
    const accelerometer = this.accelerometerCallback;
    this.accelerometerCallback = undefined;
    if (accelerometer !== undefined) {
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER, accelerometer);
      } catch (_error) {
      }
    }
    const compass = this.compassCallback;
    this.compassCallback = undefined;
    if (compass !== undefined) {
      try {
        sensor.off(sensor.SensorId.ORIENTATION, compass);
      } catch (_error) {
      }
    }
    this.context = undefined;
  }

  private emit(payload: SensorEventPayload): void {
    if (!this.destroyed) {
      this.context?.sendGlobalEvent(SensorsModule.EVENT_NAME, [payload]);
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

class SensorsLifecycleClient extends LynxViewClient {
  private readonly controller: NativeSensorsController;

  constructor(controller: NativeSensorsController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}

/** HarmonyOS motion sensors exported to Lynx as Sensors. */
export class SensorsModule extends LynxModule {
  static readonly NAME: string = 'Sensors';
  static readonly EVENT_NAME: string = 'sensors';
  private readonly controller: NativeSensorsController;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.controller = new NativeSensorsController();
    context.getLynxViewClient()?.push(new SensorsLifecycleClient(this.controller));
  }

  isAvailable(type: string, callback: (resultJSON: string) => void): void {
    this.controller.isAvailable(type, callback);
  }

  start(type: string, callback: (error: string) => void): void {
    this.controller.start(type, callback, this.context);
  }

  stop(type: string, callback: (error: string) => void): void {
    this.controller.stop(type, callback);
  }
}
