import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class NativeNotifyOptions {
  id: string;
  title: string;
  body: string;
  delayMs: number;
  sound: boolean;

  constructor(id: string, title: string, body: string, delayMs: number, sound: boolean) {
    this.id = id;
    this.title = title;
    this.body = body;
    this.delayMs = delayMs;
    this.sound = sound;
  }
}

interface NativeNotifyInput {
  id: string;
  title: string;
  body?: string;
  delayMs?: number;
  sound?: boolean;
}

class NativeNotifyOutcome {
  code: string;
  message: string;

  constructor(code: string, message: string) {
    this.code = code;
    this.message = message;
  }
}

class NativeNotifyResult {
  value: NativeNotifyOutcome | null;
  error: string;

  constructor(value: NativeNotifyOutcome | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/**
 * Local notifications exported to Lynx as LocalNotification.
 *
 * Notification permission is requested through the separate Permissions
 * module; notify only checks the enablement gate. Delayed delivery uses
 * in-process timers, so pending notifications do not outlive the app
 * process; cancelAll also only covers ids posted by this instance.
 */
export class LocalNotificationModule extends LynxModule {
  static readonly NAME: string = 'LocalNotification';

  private static readonly MAX_DELAY_MS: number = 7 * 24 * 60 * 60 * 1000;

  /** Pending timers by notification id; HarmonyOS timers are numeric. */
  private readonly timers: Map<string, number> = new Map();
  /** Ids delivered by this instance, for cancelAll. */
  private readonly delivered: Set<string> = new Set();
  private slotReady = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  notify(rawOptions: NativeNotifyInput,
    callback: (result: NativeNotifyResult) => void): void {
    let options: NativeNotifyOptions;
    try {
      options = this.parseOptions(rawOptions);
    } catch (error) {
      callback(new NativeNotifyResult(null, this.messageOf(error)));
      return;
    }
    notificationManager
      .isNotificationEnabled()
      .then((enabled: boolean) => {
        if (!enabled) {
          callback(new NativeNotifyResult(new NativeNotifyOutcome(
            'permissionDenied',
            'Notifications are disabled; request the notification permission' +
              ' (Permissions module) or enable them in system settings',
          )));
          return;
        }
        if (options.delayMs > 0) {
          this.scheduleDelivery(options)
            .then(() => {
              callback(new NativeNotifyResult(new NativeNotifyOutcome('success', '')));
            })
            .catch((error: BusinessError) => {
              callback(new NativeNotifyResult(new NativeNotifyOutcome(
                'unavailable', this.messageOf(error),
              )));
            });
          return;
        }
        this.publish(options)
          .then(() => {
            callback(new NativeNotifyResult(new NativeNotifyOutcome('success', '')));
          })
          .catch((error: BusinessError) => {
            callback(new NativeNotifyResult(new NativeNotifyOutcome(
              'unavailable', this.messageOf(error),
            )));
          });
      })
      .catch((error: BusinessError) => {
        callback(new NativeNotifyResult(new NativeNotifyOutcome(
          'unavailable', this.messageOf(error),
        )));
      });
  }

  cancel(id: string, callback: (error: string) => void): void {
    if (id === null || id === undefined || id.trim().length === 0) {
      callback('LocalNotification id must not be empty');
      return;
    }
    const timer = this.timers.get(id);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.timers.delete(id);
    }
    notificationManager
      .cancel(LocalNotificationModule.stableId(id))
      .then(() => {
        this.delivered.delete(id);
        callback('');
      })
      .catch((error: BusinessError) => {
        callback(this.messageOf(error));
      });
  }

  cancelAll(callback: (error: string) => void): void {
    for (const timer of this.timers.values()) {
      clearTimeout(timer);
    }
    this.timers.clear();
    const ids: string[] = [];
    this.delivered.forEach((id: string) => {
      ids.push(id);
    });
    let failure: string = '';
    let pending = ids.length;
    if (pending === 0) {
      callback('');
      return;
    }
    const settle = (): void => {
      pending -= 1;
      if (pending === 0) {
        this.delivered.clear();
        callback(failure);
      }
    };
    for (const id of ids) {
      notificationManager
        .cancel(LocalNotificationModule.stableId(id))
        .then(() => {
          settle();
        })
        .catch((error: BusinessError) => {
          if (failure.length === 0) {
            failure = this.messageOf(error);
          }
          settle();
        });
    }
  }

  private async scheduleDelivery(options: NativeNotifyOptions): Promise<void> {
    const previous = this.timers.get(options.id);
    if (previous !== undefined) {
      clearTimeout(previous);
    }
    try {
      await notificationManager.cancel(LocalNotificationModule.stableId(options.id));
    } catch (error) {
      // There may be no delivered notification with this id yet.
    }
    this.delivered.delete(options.id);
    const timer: number = setTimeout(() => {
      this.timers.delete(options.id);
      this.publish(options).catch(() => {
        // The enablement gate was checked at scheduling time; a refusal
        // in between simply drops the notification.
      });
    }, options.delayMs);
    this.timers.set(options.id, timer);
  }

  private async publish(options: NativeNotifyOptions): Promise<void> {
    // An immediate call with the same id replaces an older delayed call.
    const pending = this.timers.get(options.id);
    if (pending !== undefined) {
      clearTimeout(pending);
      this.timers.delete(options.id);
    }
    await this.ensureSlot();
    const request: notificationManager.NotificationRequest = {
      id: LocalNotificationModule.stableId(options.id),
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType:
          notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: options.title,
          text: options.body,
          additionalText: '',
        },
      },
    };
    await notificationManager.publish(request);
    this.delivered.add(options.id);
  }

  private async ensureSlot(): Promise<void> {
    if (this.slotReady) {
      return;
    }
    try {
      await notificationManager.addSlot(
        notificationManager.SlotType.SERVICE_INFORMATION,
      );
    } catch (error) {
      // addSlot reports the slot as existing on repeat calls; any other
      // failure surfaces through publish right after.
    }
    this.slotReady = true;
  }

  private parseOptions(raw: NativeNotifyInput): NativeNotifyOptions {
    const rawId = raw?.id;
    const rawTitle = raw?.title;
    const id = typeof rawId === 'string' ? rawId : '';
    const title = typeof rawTitle === 'string' ? rawTitle : '';
    if (id.trim().length === 0) {
      throw new Error('LocalNotification id must not be empty');
    }
    if (title.trim().length === 0) {
      throw new Error('LocalNotification title must not be empty');
    }
    const rawDelay = raw?.delayMs;
    const delayMs = rawDelay === undefined ? 0 : Number(rawDelay);
    if (!Number.isFinite(delayMs) || delayMs < 0 ||
        delayMs > LocalNotificationModule.MAX_DELAY_MS) {
      throw new Error(
        `LocalNotification delayMs must be between 0 and ${LocalNotificationModule.MAX_DELAY_MS}`,
      );
    }
    const rawBody = raw?.body;
    const rawSound = raw?.sound;
    return new NativeNotifyOptions(
      id,
      title,
      typeof rawBody === 'string' ? rawBody : '',
      delayMs,
      rawSound === undefined ? true : rawSound === true,
    );
  }

  /** Deterministic 32-bit hash so the same string id cancels what it posted. */
  private static stableId(id: string): number {
    let hash = 5381;
    for (let index = 0; index < id.length; index += 1) {
      hash = ((hash << 5) + hash + id.charCodeAt(index)) | 0;
    }
    const positive = hash & 0x7fffffff;
    return positive === 0 ? 1 : positive;
  }

  private messageOf(error: Error | BusinessError): string {
    const message = error.message;
    return message.length > 0 ? message : 'Unknown notification error';
  }
}
