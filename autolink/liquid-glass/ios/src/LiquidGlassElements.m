#import <UIKit/UIKit.h>

#import <Lynx/LynxEvent.h>
#import <Lynx/LynxEventEmitter.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUI.h>

@interface LynxUIGlassSwitch : LynxUI<UISwitch *>
@end

@LynxElement("glass-switch")
@implementation LynxUIGlassSwitch

- (UISwitch *)createView {
  UISwitch *toggle = [[UISwitch alloc] init];
  [toggle addTarget:self
                action:@selector(handleValueChanged:)
      forControlEvents:UIControlEventValueChanged];
  return toggle;
}

LYNX_PROP_SETTER("checked", setChecked, BOOL) {
  [self.view setOn:(!requestReset && value) animated:YES];
}

LYNX_PROP_SETTER("disabled", setDisabled, BOOL) {
  self.view.enabled = requestReset ? YES : !value;
}

- (void)handleValueChanged:(UISwitch *)sender {
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"change"
                                targetSign:self.sign
                                    detail:@{ @"value" : @(sender.on) }];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

@end

@interface LynxUIGlassDropdown : LynxUI<UIButton *>

@property(nonatomic, copy) NSString *placeholderTitle;
@property(nonatomic, copy) NSArray<NSString *> *options;
@property(nonatomic, assign) NSInteger selectedIndex;

@end

@LynxElement("glass-dropdown")
@implementation LynxUIGlassDropdown

- (instancetype)initWithView:(UIButton *)view {
  self = [super initWithView:view];
  if (self) {
    _placeholderTitle = @"";
    _options = @[];
    _selectedIndex = -1;
  }
  return self;
}

- (UIButton *)createView {
  // Lynx owns the visible trigger and selected label. This transparent native
  // button only gives UIMenu a correctly positioned presentation source; on
  // iOS 26 the system menu receives Liquid Glass automatically.
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.backgroundColor = UIColor.clearColor;

  if (@available(iOS 14.0, *)) {
    button.showsMenuAsPrimaryAction = YES;
    if (@available(iOS 15.0, *)) {
      // Keep selection controlled by Lynx. UIKit's automatic pop-up mode
      // selects the first action as soon as the menu is assigned.
      button.changesSelectionAsPrimaryAction = NO;
    }
  } else {
    [button addTarget:self
                  action:@selector(handleLegacyTap)
        forControlEvents:UIControlEventTouchUpInside];
  }
  return button;
}

LYNX_PROP_SETTER("title", setTitle, NSString *) {
  self.placeholderTitle = requestReset ? @"" : (value ?: @"");
  [self applyContent];
}

LYNX_PROP_SETTER("options", setOptions, NSArray *) {
  NSArray<NSString *> *nextOptions = @[];
  if (!requestReset && [value isKindOfClass:NSArray.class]) {
    BOOL containsOnlyStrings = YES;
    for (id option in value) {
      if (![option isKindOfClass:NSString.class]) {
        containsOnlyStrings = NO;
        break;
      }
    }
    if (containsOnlyStrings) {
      nextOptions = [value copy];
    }
  }
  self.options = nextOptions;
  if (self.selectedIndex >= (NSInteger)self.options.count) {
    self.selectedIndex = -1;
  }
  [self applyContent];
}

LYNX_PROP_SETTER("selected", setSelected, NSInteger) {
  self.selectedIndex = requestReset ? -1 : value;
  [self applyContent];
}

LYNX_PROP_SETTER("disabled", setDisabled, BOOL) {
  self.view.enabled = requestReset ? YES : !value;
}

- (void)applyContent {
  NSString *label =
      self.selectedIndex >= 0 &&
              self.selectedIndex < (NSInteger)self.options.count
          ? self.options[(NSUInteger)self.selectedIndex]
          : (self.placeholderTitle.length == 0 ? @"Select…"
                                                : self.placeholderTitle);
  self.view.accessibilityLabel = label;
  [self rebuildMenu];
}

- (void)rebuildMenu {
  if (@available(iOS 14.0, *)) {
    NSMutableArray<UIMenuElement *> *actions =
        [NSMutableArray arrayWithCapacity:self.options.count];
    __weak typeof(self) weakSelf = self;
    [self.options enumerateObjectsUsingBlock:^(NSString *option,
                                                NSUInteger index,
                                                BOOL *stop) {
      UIAction *action = [UIAction
          actionWithTitle:option
                    image:nil
               identifier:nil
                  handler:^(__kindof UIAction *selectedAction) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf == nil) {
                      return;
                    }
                    strongSelf.selectedIndex = (NSInteger)index;
                    [strongSelf applyContent];
                    LynxDetailEvent *event = [[LynxDetailEvent alloc]
                        initWithName:@"select"
                         targetSign:strongSelf.sign
                             detail:@{
                               @"index" : @(index),
                               @"value" : option,
                             }];
                    [strongSelf.context.eventEmitter dispatchCustomEvent:event];
                  }];
      action.state = (NSInteger)index == self.selectedIndex
                         ? UIMenuElementStateOn
                         : UIMenuElementStateOff;
      [actions addObject:action];
    }];

    if (@available(iOS 15.0, *)) {
      self.view.menu = [UIMenu menuWithTitle:@""
                                      image:nil
                                 identifier:nil
                                    options:UIMenuOptionsSingleSelection
                                   children:actions];
    } else {
      self.view.menu = [UIMenu menuWithChildren:actions];
    }
  }
}

- (void)handleLegacyTap {
  if (self.options.count == 0) {
    return;
  }
  self.selectedIndex = (self.selectedIndex + 1) % (NSInteger)self.options.count;
  [self applyContent];
  NSString *value = self.options[(NSUInteger)self.selectedIndex];
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"select"
                                targetSign:self.sign
                                    detail:@{
                                      @"index" : @(self.selectedIndex),
                                      @"value" : value,
                                    }];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

@end
