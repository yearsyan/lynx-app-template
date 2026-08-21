import { EventHandlerArray, UIBase, UIGroup } from '@lynx/lynx';
import { NativeContent } from 'liblynx.so';

@ObservedV2
class PredictiveBackOverlayState {
  @Trace backdropColor: ResourceColor = '#73000000';
  @Trace children: NativeContent[] = [];
}

@ComponentV2
struct PredictiveBackOverlayComponent {
  @Param @Require state: PredictiveBackOverlayState;

  build() {
    Stack() {
      ForEach(this.state.children, (child: NativeContent) => {
        ContentSlot(child.content);
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.state.backdropColor);
  }
}

@Builder
function buildPredictiveBackOverlay(ui: UIBase) {
  PredictiveBackOverlayComponent({
    state: (ui as PredictiveBackOverlayUI).state,
  });
}

/** HarmonyOS keeps the same child-hosting element but has no progress API. */
export class PredictiveBackOverlayUI extends UIGroup {
  static readonly NAME: string = 'predictive-back-overlay';
  readonly state: PredictiveBackOverlayState = new PredictiveBackOverlayState();
  readonly builder: WrappedBuilder<[UIBase]> = wrapBuilder(buildPredictiveBackOverlay);

  update(props: Record<string, Object>, events?: EventHandlerArray[]): void {
    super.update(props, events);
    const backdropColor = props['backdrop-color'];
    if (typeof backdropColor === 'string' || typeof backdropColor === 'number') {
      this.state.backdropColor = backdropColor;
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
    // Lynx positions the root FrameNode and every child NativeContent.
  }

  dispose(): void {
    this.state.children = [];
    super.dispose();
  }
}
