import { BusinessError } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

interface NativeHapticImpact {
  effectId: string;
  fallbackDuration: number;
}

const IMPACT_LIGHT: NativeHapticImpact = {
  effectId: vibrator.HapticFeedback.EFFECT_SOFT,
  fallbackDuration: 15,
};
const IMPACT_MEDIUM: NativeHapticImpact = {
  effectId: vibrator.HapticFeedback.EFFECT_SHARP,
  fallbackDuration: 30,
};
const IMPACT_HEAVY: NativeHapticImpact = {
  effectId: vibrator.HapticFeedback.EFFECT_HARD,
  fallbackDuration: 60,
};

/** HarmonyOS one-shot impact feedback exported to Lynx as Haptics. */
export class HapticsModule extends LynxModule {
  static readonly NAME: string = 'Haptics';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  impact(style: string, callback: (error: string) => void): void {
    const impact = this.impactForStyle(style);
    if (impact === undefined) {
      callback(`Invalid haptic impact style: ${style}`);
      return;
    }
    this.playImpact(impact).then(() => {
      callback('');
    }).catch((error: BusinessError) => {
      // Harmony folds a disabled touch-feedback policy into the generic
      // device-operation error. Haptic feedback is best effort on Android/iOS
      // as well, so this platform-level no-op still completes.
      if (error.code === 14600101) {
        callback('');
        return;
      }
      callback(this.errorMessage(error, 'Unable to play haptic feedback'));
    });
  }

  private playImpact(impact: NativeHapticImpact): Promise<void> {
    return vibrator.isSupportEffect(impact.effectId).then((supported: boolean) => {
      if (!supported) {
        return this.playFallback(impact.fallbackDuration);
      }
      // Some Harmony devices report a preset as supported but reject it when
      // playback starts. Fall back to a short time vibration in that case.
      return vibrator.startVibration(
        {
          type: 'preset',
          effectId: impact.effectId,
        },
        { usage: 'touch' },
      ).catch((_error: Error) => this.playFallback(impact.fallbackDuration));
    });
  }

  private playFallback(duration: number): Promise<void> {
    return vibrator.startVibration(
      {
        type: 'time',
        duration: duration,
      },
      { usage: 'touch' },
    );
  }

  private impactForStyle(style: string): NativeHapticImpact | undefined {
    if (style === 'light') {
      return IMPACT_LIGHT;
    }
    if (style === 'medium') {
      return IMPACT_MEDIUM;
    }
    if (style === 'heavy') {
      return IMPACT_HEAVY;
    }
    return undefined;
  }

  private errorMessage(error: Error, fallback: string): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
