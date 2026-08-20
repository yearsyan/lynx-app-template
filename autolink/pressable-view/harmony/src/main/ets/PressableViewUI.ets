import { EventHandlerArray, UIBase, UIGroup } from '@lynx/lynx';
import { NativeContent } from 'liblynx.so';

const DEFAULT_ACTIVE_OPACITY: number = 0.7;
const TRANSPARENT_OVERLAY_COLOR: string = '#00000000';
const PRESS_FEEDBACK_DELAY_MS: number = 80;
const MINIMUM_TAP_FLASH_MS: number = 72;
const SCROLL_COOLDOWN_MS: number = 120;
const TOUCH_SLOP: number = 10;

@ObservedV2
class PressableViewState {
  @Trace activeOpacity: number = DEFAULT_ACTIVE_OPACITY;
  @Trace pressedOverlayColor: string = TRANSPARENT_OVERLAY_COLOR;
  @Trace disabled: boolean = false;
  @Trace pressed: boolean = false;
  @Trace children: NativeContent[] = [];
  readonly ui: PressableViewUI;
  private tracking: boolean = false;
  private blocked: boolean = false;
  private hasCompletedTouch: boolean = false;
  private completedTouchAccepted: boolean = false;
  private completedWithVisibleFeedback: boolean = false;
  private activeTouchId: number = -1;
  private downX: number = 0;
  private downY: number = 0;
  private sequence: number = 0;
  private lastAreaActivityMs: number = -1;

  constructor(ui: PressableViewUI) {
    this.ui = ui;
  }

  handleTouch(event: TouchEvent): void {
    switch (event.type) {
      case TouchType.Down:
        this.beginTouch(event);
        break;
      case TouchType.Move:
        this.updateTouch(event);
        break;
      case TouchType.Up:
        this.finishTouch();
        break;
      case TouchType.Cancel:
        this.cancelTouch();
        break;
      default:
        break;
    }
  }

  handleClick(): void {
    const acceptedByTouch: boolean = !this.hasCompletedTouch || this.completedTouchAccepted;
    this.hasCompletedTouch = false;
    this.completedTouchAccepted = false;
    if (this.disabled || this.isScrollingOrRecent() || !acceptedByTouch) {
      this.reset();
      return;
    }
    if (!this.completedWithVisibleFeedback) {
      const sequence = ++this.sequence;
      this.pressed = true;
      setTimeout(() => {
        if (sequence === this.sequence && !this.tracking) {
          this.pressed = false;
        }
      }, MINIMUM_TAP_FLASH_MS);
    }
    this.completedWithVisibleFeedback = false;
    this.ui.emitPress();
  }

  reset(): void {
    this.cancelTouch();
    this.completedWithVisibleFeedback = false;
  }

  handleAreaChange(oldValue: Area, newValue: Area): void {
    if (oldValue.globalPosition.x === newValue.globalPosition.x &&
      oldValue.globalPosition.y === newValue.globalPosition.y) {
      return;
    }
    this.lastAreaActivityMs = new Date().getTime();
    if (this.tracking) {
      this.blockCurrentTouch();
    }
  }

  private beginTouch(event: TouchEvent): void {
    this.sequence += 1;
    this.pressed = false;
    this.completedWithVisibleFeedback = false;
    this.hasCompletedTouch = false;
    this.completedTouchAccepted = false;
    this.tracking = !this.disabled;
    this.blocked = !this.tracking || this.isScrollingOrRecent();

    const touch = this.firstTouch(event);
    if (touch === undefined) {
      this.blockCurrentTouch();
      return;
    }
    this.activeTouchId = touch.id;
    this.downX = touch.windowX;
    this.downY = touch.windowY;

    const sequence = this.sequence;
    setTimeout(() => {
      if (sequence === this.sequence && this.tracking && !this.blocked && !this.disabled &&
        !this.isScrollingOrRecent()) {
        this.pressed = true;
      }
    }, PRESS_FEEDBACK_DELAY_MS);
  }

  private updateTouch(event: TouchEvent): void {
    if (!this.tracking || this.blocked) {
      return;
    }
    const touch = this.touchWithId(event, this.activeTouchId);
    if (touch === undefined) {
      this.blockCurrentTouch();
      return;
    }
    const deltaX = touch.windowX - this.downX;
    const deltaY = touch.windowY - this.downY;
    if (deltaX * deltaX + deltaY * deltaY > TOUCH_SLOP * TOUCH_SLOP) {
      this.blockCurrentTouch();
    }
  }

  private finishTouch(): void {
    const accepted: boolean = this.tracking && !this.blocked && !this.disabled &&
      !this.isScrollingOrRecent();
    this.hasCompletedTouch = true;
    this.completedTouchAccepted = accepted;
    this.completedWithVisibleFeedback = accepted && this.pressed;
    this.tracking = false;
    this.blocked = false;
    this.activeTouchId = -1;
    this.sequence += 1;
    this.pressed = false;
  }

  private cancelTouch(): void {
    this.tracking = false;
    this.blocked = false;
    this.hasCompletedTouch = false;
    this.completedTouchAccepted = false;
    this.activeTouchId = -1;
    this.sequence += 1;
    this.pressed = false;
  }

  private blockCurrentTouch(): void {
    this.blocked = true;
    this.sequence += 1;
    this.pressed = false;
  }

  private firstTouch(event: TouchEvent): TouchObject | undefined {
    if (event.touches.length > 0) {
      return event.touches[0];
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    return undefined;
  }

  private touchWithId(event: TouchEvent, id: number): TouchObject | undefined {
    for (let index = 0; index < event.touches.length; index += 1) {
      if (event.touches[index].id === id) {
        return event.touches[index];
      }
    }
    return undefined;
  }

  private isScrollingOrRecent(): boolean {
    return this.lastAreaActivityMs >= 0 &&
      new Date().getTime() - this.lastAreaActivityMs <= SCROLL_COOLDOWN_MS;
  }
}

@ComponentV2
struct PressableViewComponent {
  @Param @Require state: PressableViewState;

  build() {
    Button({ type: ButtonType.Normal }) {
      Stack() {
        ForEach(this.state.children, (child: NativeContent) => {
          ContentSlot(child.content);
        });
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.state.pressed ? this.state.pressedOverlayColor : TRANSPARENT_OVERLAY_COLOR);
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(0)
    .borderRadius(0)
    .backgroundColor(Color.Transparent)
    .enabled(!this.state.disabled)
    .stateEffect(false)
    .opacity(this.state.pressed ? this.state.activeOpacity : 1)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.state.handleAreaChange(oldValue, newValue);
    })
    .onTouch((event: TouchEvent) => {
      this.state.handleTouch(event);
    })
    .onClick(() => {
      this.state.handleClick();
    });
  }
}

@Builder
function buildPressableView(ui: UIBase) {
  PressableViewComponent({ state: (ui as PressableViewUI).state });
}

/** ArkUI child-hosting press target backed by the native Button recognizer. */
export class PressableViewUI extends UIGroup {
  static readonly NAME: string = 'pressable-view';
  readonly state: PressableViewState = new PressableViewState(this);
  readonly builder: WrappedBuilder<[UIBase]> = wrapBuilder(buildPressableView);

  update(props: Record<string, Object>, events?: EventHandlerArray[]): void {
    super.update(props, events);
    const activeOpacity = props['active-opacity'];
    if (typeof activeOpacity === 'number') {
      this.state.activeOpacity = Math.max(0, Math.min(1, activeOpacity));
    }
    const pressedOverlayColor = props['pressed-overlay-color'];
    const normalizedOverlayColor = normalizeOverlayColor(pressedOverlayColor);
    if (normalizedOverlayColor !== undefined) {
      this.state.pressedOverlayColor = normalizedOverlayColor;
    }
    const disabled = props['disabled'];
    if (typeof disabled === 'boolean') {
      this.state.disabled = disabled;
      if (disabled) {
        this.state.reset();
      }
    }
  }

  hasCustomizedLayout(): boolean {
    return true;
  }

  insertChild(nativeContent: NativeContent, index: number): void {
    this.children.splice(index, 0, nativeContent);
    this.state.children = this.children.slice();
  }

  removeChild(nativeContent: NativeContent): void {
    const index = this.children.indexOf(nativeContent);
    if (index >= 0) {
      this.children.splice(index, 1);
      this.state.children = this.children.slice();
    }
  }

  layout(x: number, y: number, width: number, height: number,
    paddingLeft: number, paddingTop: number, paddingRight: number,
    paddingBottom: number, marginLeft: number, marginTop: number,
    marginRight: number, marginBottom: number, sticky?: number[]): void {
    // Lynx positions the root FrameNode and each child NativeContent.
  }

  emitPress(): void {
    if (!this.state.disabled) {
      this.sendCustomEvent('press', {}, 'detail');
    }
  }

  dispose(): void {
    this.state.reset();
    this.state.disabled = true;
    this.state.children = [];
    super.dispose();
  }
}

function normalizeOverlayColor(value: Object): string | undefined {
  if (typeof value === 'number') {
    let packedColor = Math.trunc(value);
    if (packedColor < 0) {
      packedColor += 4294967296;
    }
    return `#${packedColor.toString(16).padStart(8, '0').toUpperCase()}`;
  }
  if (typeof value !== 'string') {
    return undefined;
  }

  const color = value.trim();
  const lowerColor = color.toLowerCase();
  if (lowerColor === 'transparent') {
    return TRANSPARENT_OVERLAY_COLOR;
  }
  if (color.startsWith('#')) {
    return normalizeHexColor(color);
  }
  if (lowerColor.startsWith('rgba(') && lowerColor.endsWith(')')) {
    return normalizeFunctionalColor(lowerColor.substring(5, lowerColor.length - 1), true);
  }
  if (lowerColor.startsWith('rgb(') && lowerColor.endsWith(')')) {
    return normalizeFunctionalColor(lowerColor.substring(4, lowerColor.length - 1), false);
  }
  return color;
}

function normalizeHexColor(color: string): string {
  const hex = color.substring(1);
  if (hex.length === 3) {
    return `#FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}`.toUpperCase();
  }
  if (hex.length === 4) {
    return `#${hex[3]}${hex[3]}${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}`.toUpperCase();
  }
  if (hex.length === 6) {
    return `#FF${hex}`.toUpperCase();
  }
  if (hex.length === 8) {
    return `#${hex.substring(6, 8)}${hex.substring(0, 6)}`.toUpperCase();
  }
  return color;
}

function normalizeFunctionalColor(componentsText: string, includesAlpha: boolean): string | undefined {
  const components = componentsText.split(',');
  if (components.length !== (includesAlpha ? 4 : 3)) {
    return undefined;
  }
  const red = normalizeRgbComponent(components[0]);
  const green = normalizeRgbComponent(components[1]);
  const blue = normalizeRgbComponent(components[2]);
  const alpha = includesAlpha ? normalizeAlphaComponent(components[3]) : 255;
  if (red === undefined || green === undefined || blue === undefined || alpha === undefined) {
    return undefined;
  }
  return `#${toHex(alpha)}${toHex(red)}${toHex(green)}${toHex(blue)}`;
}

function normalizeRgbComponent(component: string): number | undefined {
  const value = Number.parseFloat(component.trim());
  if (!Number.isFinite(value)) {
    return undefined;
  }
  return Math.round(Math.max(0, Math.min(255, value)));
}

function normalizeAlphaComponent(component: string): number | undefined {
  const value = Number.parseFloat(component.trim());
  if (!Number.isFinite(value)) {
    return undefined;
  }
  return Math.round(Math.max(0, Math.min(1, value)) * 255);
}

function toHex(value: number): string {
  return value.toString(16).padStart(2, '0').toUpperCase();
}
