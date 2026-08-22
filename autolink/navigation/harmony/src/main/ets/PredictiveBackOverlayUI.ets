import { EventHandlerArray, UIBase, UIGroup } from '@lynx/lynx';
import { NativeContent } from 'liblynx.so';

const ENTER_DURATION_MS: number = 340;
const EXIT_DURATION_MS: number = 260;
const SETTLE_DURATION_MS: number = 220;
const TOUCH_SLOP: number = 10;
const MINIMUM_DISMISS_VELOCITY: number = 900;

@ObservedV2
class PredictiveBackOverlayState {
  @Trace backdropColor: ResourceColor = '#73000000';
  @Trace children: NativeContent[] = [];
  @Trace progress: number = 1;
  @Trace motion: string = 'sheet';
  @Trace animationDuration: number = 1;
  @Trace dragging: boolean = false;
  @Trace dragOffsetY: number = 0;
  @Trace width: number = 0;
  @Trace height: number = 0;
  readonly ui: PredictiveBackOverlayUI;
  private animatePresence: boolean = true;
  private dragToDismiss: boolean = false;
  private dragDismissThreshold: number = 0.22;
  private contentHeightRatio: number = 0;
  private presented: boolean = false;
  private presentationResolved: boolean = false;
  private presentationPending: boolean = false;
  private tracking: boolean = false;
  private backdropTracking: boolean = false;
  private backdropPressCandidate: boolean = false;
  private activeTouchId: number = -1;
  private downX: number = 0;
  private downY: number = 0;
  private downTimeMs: number = 0;
  private globalY: number = 0;
  private sequence: number = 0;

  constructor(ui: PredictiveBackOverlayUI) {
    this.ui = ui;
  }

  setMotion(value: string): void {
    this.motion = value === 'horizontal' || value === 'none' ? value : 'sheet';
  }

  setAnimatePresence(value: boolean): void {
    this.animatePresence = value;
  }

  setDragToDismiss(value: boolean): void {
    this.dragToDismiss = value;
    if (!value) {
      this.cancelDrag();
    }
  }

  setDragDismissThreshold(value: number): void {
    this.dragDismissThreshold = Math.max(0.05, Math.min(0.9, value));
  }

  setContentHeightRatio(value: number): void {
    this.contentHeightRatio = Math.max(0, Math.min(1, value));
    this.applyPendingPresentation();
  }

  setPresented(value: boolean): void {
    if (this.presentationResolved && this.presented === value) {
      return;
    }
    this.presentationResolved = true;
    this.presented = value;
    this.cancelDragTracking();
    this.presentationPending = true;
    this.applyPendingPresentation();
  }

  private applyPendingPresentation(): void {
    if (!this.presentationPending || this.height <= 0 ||
      (this.motion === 'sheet' && this.contentHeightRatio <= 0)) {
      return;
    }
    this.presentationPending = false;
    const target: number = this.presented ? 0 : 1;
    const fullDuration: number = this.presented ? ENTER_DURATION_MS : EXIT_DURATION_MS;
    const duration: number = this.animatePresence ?
      Math.round(fullDuration * Math.abs(target - this.progress)) : 0;
    this.animationDuration = Math.max(1, duration);
    this.progress = target;
    this.scheduleTransitionEnd(this.presented, duration);
  }

  handleAreaChange(newValue: Area): void {
    this.width = Number(newValue.width);
    this.height = Number(newValue.height);
    this.globalY = Number(newValue.globalPosition.y);
    this.applyPendingPresentation();
  }

  handleTouch(event: TouchEvent): void {
    switch (event.type) {
      case TouchType.Down:
        this.beginDrag(event);
        break;
      case TouchType.Move:
        this.updateDrag(event);
        break;
      case TouchType.Up:
        this.finishDrag(event, false);
        break;
      case TouchType.Cancel:
        this.finishDrag(event, true);
        break;
      default:
        break;
    }
  }

  contentTranslationX(): number {
    return this.motion === 'horizontal' ? this.width * this.progress : 0;
  }

  contentTranslationY(): number {
    if (this.motion !== 'sheet') {
      return 0;
    }
    return this.dragging ? this.dragOffsetY : this.dragTravelHeight() * this.progress;
  }

  reset(): void {
    this.sequence += 1;
    this.cancelDragTracking();
    this.progress = 1;
    this.children = [];
  }

  private beginDrag(event: TouchEvent): void {
    this.cancelDragTracking();
    if (!this.presented || this.progress > 0.001 || this.height <= 0) {
      return;
    }
    const touch = this.firstTouch(event);
    if (touch === undefined) {
      return;
    }
    if (touch.windowY - this.globalY < this.height - this.dragTravelHeight()) {
      this.backdropTracking = true;
      this.backdropPressCandidate = true;
      this.activeTouchId = touch.id;
      this.downX = touch.windowX;
      this.downY = touch.windowY;
      return;
    }
    if (!this.dragToDismiss || this.motion !== 'sheet') {
      return;
    }
    this.tracking = true;
    this.activeTouchId = touch.id;
    this.downX = touch.windowX;
    this.downY = touch.windowY;
    this.downTimeMs = new Date().getTime();
  }

  private updateDrag(event: TouchEvent): void {
    if (this.backdropTracking) {
      const backdropTouch = this.touchWithId(event, this.activeTouchId);
      if (backdropTouch === undefined ||
        Math.abs(backdropTouch.windowX - this.downX) > TOUCH_SLOP ||
        Math.abs(backdropTouch.windowY - this.downY) > TOUCH_SLOP) {
        this.backdropPressCandidate = false;
      }
      return;
    }
    if (!this.tracking) {
      return;
    }
    const touch = this.touchWithId(event, this.activeTouchId);
    if (touch === undefined) {
      this.cancelDrag();
      return;
    }
    const deltaX: number = touch.windowX - this.downX;
    const deltaY: number = touch.windowY - this.downY;
    if (!this.dragging) {
      if (deltaY > TOUCH_SLOP && deltaY > Math.abs(deltaX) * 1.05) {
        this.dragging = true;
        this.animationDuration = 1;
      } else if (Math.abs(deltaX) > TOUCH_SLOP || deltaY < -TOUCH_SLOP) {
        this.cancelDragTracking();
        return;
      }
    }
    if (this.dragging) {
      this.dragOffsetY = Math.max(0, deltaY);
      this.progress = Math.min(1, this.dragOffsetY / this.dragTravelHeight());
    }
  }

  private finishDrag(event: TouchEvent, cancelled: boolean): void {
    if (this.backdropTracking) {
      const touch = this.changedTouchWithId(event, this.activeTouchId);
      const shouldEmit: boolean = !cancelled && this.backdropPressCandidate &&
        touch !== undefined && Math.abs(touch.windowX - this.downX) <= TOUCH_SLOP &&
        Math.abs(touch.windowY - this.downY) <= TOUCH_SLOP;
      this.cancelDragTracking();
      if (shouldEmit) {
        this.ui.emitBackdropPress();
      }
      return;
    }
    if (!this.tracking || !this.dragging) {
      this.cancelDragTracking();
      return;
    }
    const touch = this.changedTouchWithId(event, this.activeTouchId);
    const now: number = new Date().getTime();
    const velocityY: number = touch === undefined ? 0 :
      Math.max(0, touch.windowY - this.downY) / Math.max(1, now - this.downTimeMs) * 1000;
    const shouldDismiss: boolean = !cancelled &&
      (this.progress >= this.dragDismissThreshold ||
        (this.progress >= 0.04 && velocityY >= MINIMUM_DISMISS_VELOCITY));
    const start: number = this.progress;
    this.cancelDragTracking();
    const target: number = shouldDismiss ? 1 : 0;
    const fullDuration: number = shouldDismiss ? EXIT_DURATION_MS : SETTLE_DURATION_MS;
    const duration: number = Math.round(fullDuration * Math.abs(target - start));
    this.animationDuration = Math.max(1, duration);
    this.progress = target;
    if (shouldDismiss) {
      const sequence: number = ++this.sequence;
      setTimeout(() => {
        if (sequence === this.sequence && this.presented) {
          this.ui.emitDragDismiss();
        }
      }, duration);
    }
  }

  private cancelDrag(): void {
    const start: number = this.progress;
    const wasDragging: boolean = this.dragging;
    this.cancelDragTracking();
    if (wasDragging) {
      this.animationDuration = Math.max(1,
        Math.round(SETTLE_DURATION_MS * Math.abs(start)));
      this.progress = 0;
    }
  }

  private cancelDragTracking(): void {
    this.tracking = false;
    this.dragging = false;
    this.backdropTracking = false;
    this.backdropPressCandidate = false;
    this.activeTouchId = -1;
    this.dragOffsetY = 0;
  }

  private dragTravelHeight(): number {
    return Math.max(1, this.height * this.contentHeightRatio);
  }

  private scheduleTransitionEnd(presented: boolean, duration: number): void {
    const sequence: number = ++this.sequence;
    setTimeout(() => {
      if (sequence === this.sequence && this.presented === presented) {
        this.ui.emitTransitionEnd(presented);
      }
    }, duration);
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

  private changedTouchWithId(event: TouchEvent, id: number): TouchObject | undefined {
    for (let index = 0; index < event.changedTouches.length; index += 1) {
      if (event.changedTouches[index].id === id) {
        return event.changedTouches[index];
      }
    }
    return undefined;
  }
}

@ComponentV2
struct PredictiveBackOverlayComponent {
  @Param @Require state: PredictiveBackOverlayState;

  build() {
    Stack() {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.state.backdropColor)
        .opacity(1 - this.state.progress)
        .animation({
          duration: this.state.animationDuration,
          curve: Curve.Friction,
        });
      Stack() {
        ForEach(this.state.children, (child: NativeContent) => {
          ContentSlot(child.content);
        });
      }
      .width('100%')
      .height('100%')
      .translate({
        x: this.state.contentTranslationX(),
        y: this.state.contentTranslationY(),
      })
      .animation({
        duration: this.state.animationDuration,
        curve: Curve.Friction,
      });
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.state.handleAreaChange(newValue);
    })
    .onTouch((event: TouchEvent) => {
      this.state.handleTouch(event);
    });
  }
}

@Builder
function buildPredictiveBackOverlay(ui: UIBase) {
  PredictiveBackOverlayComponent({
    state: (ui as PredictiveBackOverlayUI).state,
  });
}

/** HarmonyOS has discrete system Back but still owns presence and drag locally. */
export class PredictiveBackOverlayUI extends UIGroup {
  static readonly NAME: string = 'predictive-back-overlay';
  readonly state: PredictiveBackOverlayState = new PredictiveBackOverlayState(this);
  readonly builder: WrappedBuilder<[UIBase]> = wrapBuilder(buildPredictiveBackOverlay);

  update(props: Record<string, Object>, events?: EventHandlerArray[]): void {
    super.update(props, events);
    const backdropColor = props['backdrop-color'];
    if (typeof backdropColor === 'string' || typeof backdropColor === 'number') {
      this.state.backdropColor = backdropColor;
    }
    const motion = props['motion'];
    if (typeof motion === 'string') {
      this.state.setMotion(motion);
    }
    const animatePresence = props['animate-presence'];
    if (typeof animatePresence === 'boolean') {
      this.state.setAnimatePresence(animatePresence);
    }
    const dragToDismiss = props['drag-to-dismiss'];
    if (typeof dragToDismiss === 'boolean') {
      this.state.setDragToDismiss(dragToDismiss);
    }
    const dragDismissThreshold = props['drag-dismiss-threshold'];
    if (typeof dragDismissThreshold === 'number') {
      this.state.setDragDismissThreshold(dragDismissThreshold);
    }
    const contentHeightRatio = props['content-height-ratio'];
    if (typeof contentHeightRatio === 'number') {
      this.state.setContentHeightRatio(contentHeightRatio);
    }
    const presented = props['presented'];
    if (typeof presented === 'boolean') {
      this.state.setPresented(presented);
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
    // Lynx positions the root FrameNode. Children render through the
    // ContentSlot inside this builder and bottom-anchor themselves, so no
    // per-child positioning is needed here.
  }

  emitTransitionEnd(presented: boolean): void {
    this.sendCustomEvent('overlaytransitionend', { 'presented': presented }, 'detail');
  }

  emitDragDismiss(): void {
    this.sendCustomEvent('dragdismiss', {}, 'detail');
  }

  emitBackdropPress(): void {
    this.sendCustomEvent('backdroppress', {}, 'detail');
  }

  dispose(): void {
    this.state.reset();
    super.dispose();
  }
}
