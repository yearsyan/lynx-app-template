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
    vibrator.isSupportEffect(impact.effectId).then((supported: boolean) => {
      if (supported) {
        return vibrator.startVibration(
          {
            type: 'preset',
            effectId: impact.effectId,
          },
          { usage: 'touch' },
        );
      }
      return vibrator.startVibration(
        {
          type: 'time',
          duration: impact.fallbackDuration,
        },
        { usage: 'touch' },
      );
    }).then(() => {
      callback('');
    }).catch((error: Error) => {
      callback(this.errorMessage(error, 'Unable to play haptic feedback'));
    });
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
