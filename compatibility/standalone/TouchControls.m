#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <math.h>
#import <dlfcn.h>
extern void ShimPostVirtualKey(unsigned short, BOOL, NSString *);
extern void ShimSetAspectFill(BOOL);
extern unsigned ShimPresentedFPS(void);
int ShimTargetFPS(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:@"JSBTargetFPS"] == 120 ? 120 : 60;
}


@interface JSBTouchOverlay : UIView
@property UIView *stick, *knob;
@property NSMutableSet<NSNumber *> *held, *touchHeld, *controllerHeld;
@property CADisplayLink *displayLink;
@property UILabel *uiRate;
@property NSUInteger uiFrames;
@property CFTimeInterval uiSample;
@property UITouch *stickTouch;
@property UIButton *settingsButton;
@property UILabel *fps;
@property UIView *panel;
@property NSInteger mode, layout;
@property BOOL fill, stats, autoHide, gameplay;
@property NSTimeInterval lastInput;
@property NSTimer *timer;
@end
@implementation JSBTouchOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.multipleTouchEnabled = YES;
        self.held = [NSMutableSet new]; self.touchHeld = [NSMutableSet new]; self.controllerHeld = [NSMutableSet new];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        self.mode = [d integerForKey:@"JSBControlMode"]; if (self.mode == 1) self.mode = 0; self.layout = [d integerForKey:@"JSBLayout"];
        self.fill = NO; [d removeObjectForKey:@"JSBZoomCrop"]; self.stats = [d boolForKey:@"JSBFPS"];
        self.autoHide = [d boolForKey:@"JSBAutoHide"]; self.gameplay = [d boolForKey:@"JSBGameplay"];
        self.lastInput = NSProcessInfo.processInfo.systemUptime;
        self.stick = [UIView new]; self.stick.userInteractionEnabled = NO;
        self.stick.backgroundColor = [UIColor colorWithRed:0.03 green:0.08 blue:0.1 alpha:0.4];
        self.stick.layer.borderColor = [UIColor colorWithRed:0.1 green:0.85 blue:0.9 alpha:0.55].CGColor;
        self.stick.layer.borderWidth = 2;
        [self addSubview:self.stick];
        self.knob = [UIView new]; self.knob.userInteractionEnabled = NO;
        self.knob.backgroundColor = [UIColor colorWithRed:0.1 green:0.85 blue:0.9 alpha:0.45];
        self.knob.layer.borderColor = [UIColor colorWithRed:0.55 green:1 blue:1 alpha:0.8].CGColor; self.knob.layer.borderWidth = 1.5;
        self.knob.layer.cornerRadius = 22; [self.stick addSubview:self.knob];
        NSArray *labels = @[@"DASH", @"OK", @"BACK", @"GAME OPTIONS", @"HOLD TO LEAVE"];
        NSArray *keys = @[@49, @36, @53, @31, @8];
        for (NSUInteger i = 0; i < keys.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem]; b.tag = [keys[i] integerValue];
            [b setTitle:labels[i] forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:i > 2 ? 11 : 15 weight:UIFontWeightSemibold];
            b.backgroundColor = [UIColor colorWithRed:0.02 green:0.06 blue:0.08 alpha:0.55]; b.layer.cornerRadius = 20;
            b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
            if (b.tag == 49) { b.layer.borderColor = [UIColor colorWithRed:1 green:0.12 blue:0.5 alpha:0.8].CGColor; b.layer.borderWidth = 2; }
            [b addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
            [b addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [self addSubview:b];
        }
        self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.settingsButton setTitle:@"⚙ OPTIONS" forState:UIControlStateNormal];
        [self.settingsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.settingsButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55]; self.settingsButton.layer.cornerRadius = 14;
        [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.settingsButton];
        self.fps = [UILabel new]; self.fps.textColor = UIColor.whiteColor;
        self.fps.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        self.fps.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; self.fps.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.fps];
        [self applyMode];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(controllerFrame:)];
        [self applyFrameRate];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        __weak typeof(self) weak = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            JSBTouchOverlay *s = weak; if (!s) { [t invalidate]; return; }
            s.fps.text = [NSString stringWithFormat:@"%u FPS", ShimPresentedFPS()];
            BOOL hide = s.autoHide && !s.panel;
            s.settingsButton.alpha = hide ? 0.01 : 1;
        }];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseKeys) name:UIApplicationWillResignActiveNotification object:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ ShimSetAspectFill(self.fill); });
    }
    return self;
}
- (void)applyFrameRate {
    int fps = ShimTargetFPS();
    if (UIScreen.mainScreen.maximumFramesPerSecond < 120) fps = 60;
    self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(fps == 120 ? 80 : 60, fps, fps);
    void (*setRate)(int) = dlsym(RTLD_DEFAULT, "ShimCVSetTargetFPS");
    if (setRate) setRate(fps);
}
- (void)applyMode {
    [self releaseKeys];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat left = MAX(16, self.safeAreaInsets.left + 8), right = self.bounds.size.width - MAX(16, self.safeAreaInsets.right + 8);
    CGFloat bottom = MAX(16, self.safeAreaInsets.bottom + 8), size = self.layout == 2 ? 106 : 126;
    BOOL swapped = self.layout == 1;
    self.stick.frame = CGRectMake(swapped ? right - size : left, self.bounds.size.height - bottom - size, size, size);
    self.stick.layer.cornerRadius = size / 2; self.knob.bounds = CGRectMake(0, 0, 42, 42);
    if (!self.stickTouch) self.knob.center = CGPointMake(size / 2, size / 2);
    self.stick.hidden = self.mode == 2;
    CGFloat edge = swapped ? left : right - 90;
    for (UIView *v in self.subviews) if ([v isKindOfClass:UIButton.class] && v != self.settingsButton) {
        if (v.tag == 49) { v.frame = CGRectMake(edge, self.bounds.size.height - bottom - 90, 90, 90); v.layer.cornerRadius = 45; }
        if (v.tag == 36) v.frame = CGRectMake(swapped ? edge + 96 : edge - 100, self.bounds.size.height - bottom - 52, 94, 52);
        if (v.tag == 53) v.frame = CGRectMake(right - 70, MAX(10, self.safeAreaInsets.top), 70, 40);
        if (v.tag == 31) v.frame = CGRectMake(left + 120, MAX(10, self.safeAreaInsets.top), 116, 40);
        if (v.tag == 8) v.frame = CGRectMake(left + 242, MAX(10, self.safeAreaInsets.top), 116, 40);
        v.hidden = self.mode == 2 || (self.gameplay && (v.tag == 31 || v.tag == 8));
    }
    self.settingsButton.frame = CGRectMake(left, MAX(10, self.safeAreaInsets.top), 112, 40);
    CGFloat border = MAX(0, (self.bounds.size.width - self.bounds.size.height * 16.0 / 9.0) / 2);
    CGFloat fpsWidth = MIN(64, MAX(42, border - 6));
    self.fps.frame = CGRectMake(self.bounds.size.width - fpsWidth - 3, MAX(10, self.safeAreaInsets.top), fpsWidth, 24);
    self.fps.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium]; self.fps.hidden = !self.stats;
    if (self.panel) self.panel.frame = CGRectInset(self.bounds, MAX(20, self.safeAreaInsets.left + 12), 20);
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    if (self.settingsButton.alpha < 0.1 && CGRectContainsPoint(self.settingsButton.frame, p)) {
        self.settingsButton.alpha = 1; self.lastInput = NSProcessInfo.processInfo.systemUptime;
        return self.settingsButton;
    }
    UIView *hit = [super hitTest:p withEvent:event];
    if (hit != self) return hit;
    return !self.stick.hidden && CGRectContainsPoint(CGRectInset(self.stick.frame, -12, -12), p) ? self : nil;
}
- (NSString *)characters:(NSInteger)c {
    NSDictionary *letters = @{@0:@"a", @2:@"d", @1:@"s", @13:@"w", @31:@"o", @8:@"c", @49:@" ", @36:@"\r", @53:@"\x1b"};
    if (letters[@(c)]) return letters[@(c)];
    unichar ch = c == 123 ? 0xf702 : c == 124 ? 0xf703 : c == 125 ? 0xf701 : 0xf700;
    return [NSString stringWithCharacters:&ch length:1];
}
- (void)reconcileKeys {
    NSMutableSet *desired = [self.touchHeld mutableCopy]; [desired unionSet:self.controllerHeld];
    NSMutableSet *changed = [self.held mutableCopy]; [changed unionSet:desired];
    for (NSNumber *key in changed) {
        BOOL down = [desired containsObject:key]; if ([self.held containsObject:key] == down) continue;
        ShimPostVirtualKey(key.unsignedShortValue, down, [self characters:key.integerValue]);
    }
    self.held = desired;
}
- (void)setKey:(NSInteger)c down:(BOOL)down {
    if (down) [self.touchHeld addObject:@(c)]; else [self.touchHeld removeObject:@(c)];
    NSInteger alias = c == 123 ? 0 : c == 124 ? 2 : c == 125 ? 1 : c == 126 ? 13 : -1;
    if (alias >= 0) { if (down) [self.touchHeld addObject:@(alias)]; else [self.touchHeld removeObject:@(alias)]; }
    [self reconcileKeys];
}
- (void)controllerFrame:(CADisplayLink *)link {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    self.uiFrames++;
    if (!self.uiSample) self.uiSample = link.timestamp;
    double elapsed = link.timestamp - self.uiSample;
    if (elapsed >= 1) {
        if (self.panel) {
            self.uiRate.text = [NSString stringWithFormat:@"Interface %.0f Hz • Game %u FPS", self.uiFrames / elapsed, ShimPresentedFPS()];
            NSLog(@"SHIM JSAB settings interface %.1f Hz", self.uiFrames / elapsed);
        }
        self.uiSample = link.timestamp; self.uiFrames = 0;
    }
    NSMutableSet *wanted = [NSMutableSet new];
    static NSString *previous;
    NSArray<GCController *> *controllers = GCController.controllers;
    GCController *controller = controllers.firstObject;
    NSString *name = controller.vendorName ?: @"none";
    if (![name isEqualToString:previous]) { previous = name; NSLog(@"SHIM JSAB physical controller bridge: %@", name); }
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (pad && !self.panel) {
        float x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value;
        if (fabs(pad.dpad.xAxis.value) > fabs(x)) x = pad.dpad.xAxis.value;
        if (fabs(pad.dpad.yAxis.value) > fabs(y)) y = pad.dpad.yAxis.value;
        if (x < -0.25) [wanted addObjectsFromArray:@[@123, @0]];
        if (x > 0.25) [wanted addObjectsFromArray:@[@124, @2]];
        if (y > 0.25) [wanted addObjectsFromArray:@[@126, @13]];
        if (y < -0.25) [wanted addObjectsFromArray:@[@125, @1]];
        // DualSense Cross = A, Circle = B. Cross also confirms menu selections.
        if (pad.buttonA.pressed) [wanted addObjectsFromArray:@[@49, @36]];
        if (pad.buttonB.pressed || pad.buttonMenu.pressed) [wanted addObject:@53];
        if (pad.buttonY.pressed) [wanted addObject:@31];
    }
    self.controllerHeld = wanted; [self reconcileKeys];
}
- (void)buttonDown:(UIButton *)b {
    self.lastInput = NSProcessInfo.processInfo.systemUptime;
    b.backgroundColor = [UIColor colorWithRed:0.08 green:0.55 blue:0.6 alpha:0.75];
    [self setKey:b.tag down:YES];
}
- (void)buttonUp:(UIButton *)b {
    b.backgroundColor = [UIColor colorWithRed:0.02 green:0.06 blue:0.08 alpha:0.55];
    [self setKey:b.tag down:NO];
}
- (void)updateStick:(UITouch *)t {
    CGPoint p = [t locationInView:self.stick]; CGFloat radius = self.stick.bounds.size.width / 2;
    CGFloat x = (p.x - radius) / (radius - 15), y = (p.y - radius) / (radius - 15), length = hypot(x, y);
    if (length > 1) { x /= length; y /= length; }
    self.knob.center = CGPointMake(radius + x * (radius - 24), radius + y * (radius - 24));
    self.lastInput = NSProcessInfo.processInfo.systemUptime;
    {
        // Radial dead zone and angular hysteresis avoid chattering between cardinal/diagonal keys.
        BOOL moving = length > 0.18;
        CGFloat threshold = 0.34;
        [self setKey:123 down:moving && x < -([self.held containsObject:@123] ? 0.22 : threshold)];
        [self setKey:124 down:moving && x > ([self.held containsObject:@124] ? 0.22 : threshold)];
        [self setKey:126 down:moving && y < -([self.held containsObject:@126] ? 0.22 : threshold)];
        [self setKey:125 down:moving && y > ([self.held containsObject:@125] ? 0.22 : threshold)];
    }
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { if (!self.stickTouch) { self.stickTouch = t.anyObject; [self updateStick:self.stickTouch]; } }
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { if ([t containsObject:self.stickTouch]) [self updateStick:self.stickTouch]; }
- (void)finishTouches:(NSSet<UITouch *> *)t {
    if (![t containsObject:self.stickTouch]) return;
    for (NSNumber *key in @[@123, @124, @125, @126]) [self setKey:key.integerValue down:NO];
    self.stickTouch = nil; self.knob.center = CGPointMake(self.stick.bounds.size.width / 2, self.stick.bounds.size.height / 2);
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self finishTouches:t]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self finishTouches:t]; }
- (void)releaseKeys {
    [self.touchHeld removeAllObjects]; [self.controllerHeld removeAllObjects]; [self reconcileKeys];
    self.stickTouch = nil; self.knob.center = CGPointMake(self.stick.bounds.size.width / 2, self.stick.bounds.size.height / 2);
}
- (void)save {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setInteger:self.mode forKey:@"JSBControlMode"]; [d setInteger:self.layout forKey:@"JSBLayout"];
 [d setBool:self.stats forKey:@"JSBFPS"];
    [d setBool:self.autoHide forKey:@"JSBAutoHide"]; [d setBool:self.gameplay forKey:@"JSBGameplay"];
    [self setNeedsLayout];
}
- (void)changed:(UIControl *)sender {
    if (sender.tag == 100) { self.mode = ((UISegmentedControl *)sender).selectedSegmentIndex == 1 ? 2 : 0; [self applyMode]; }
    if (sender.tag == 101) self.layout = ((UISegmentedControl *)sender).selectedSegmentIndex;
    if (sender.tag == 103) self.stats = ((UISwitch *)sender).on;
    if (sender.tag == 104) { self.autoHide = ((UISwitch *)sender).on; self.settingsButton.alpha = self.autoHide ? 0.01 : 1; }
    if (sender.tag == 105) self.gameplay = ((UISwitch *)sender).on;
    if (sender.tag == 106) {
        [NSUserDefaults.standardUserDefaults setInteger:((UISegmentedControl *)sender).selectedSegmentIndex == 1 ? 120 : 60 forKey:@"JSBTargetFPS"];
        [self applyFrameRate];
    }
    [self save];
}
- (void)closeSettings { [self.panel removeFromSuperview]; self.panel = nil; self.lastInput = NSProcessInfo.processInfo.systemUptime; self.settingsButton.alpha = self.autoHide ? 0.01 : 1; }
- (void)showSettings {
    [self releaseKeys]; if (self.panel) { [self closeSettings]; return; }
    self.panel = [UIView new]; self.panel.backgroundColor = [UIColor colorWithRed:0.025 green:0.06 blue:0.08 alpha:1]; self.panel.opaque = YES; self.panel.layer.cornerRadius = 20;
    self.panel.frame = CGRectInset(self.bounds, MAX(20, self.safeAreaInsets.left + 12), 20); [self addSubview:self.panel];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.panel.bounds]; scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:scroll];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20], [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16], [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    UILabel *title = [UILabel new]; title.text = @"JSAB • Controls & Display"; title.textColor = UIColor.whiteColor; title.font = [UIFont boldSystemFontOfSize:20]; [stack addArrangedSubview:title];
    NSArray *names = @[@"Controller mode", @"Button layout", @"FPS stat", @"Hide Options button (tap its corner to open)", @"Gameplay layout (hide menu-only buttons)"];
    for (NSInteger i = 0; i < 5; i++) {
        UILabel *label = [UILabel new]; label.text = names[i]; label.textColor = UIColor.whiteColor; [stack addArrangedSubview:label];
        UIControl *control;
        if (i < 2) {
            UISegmentedControl *c = [[UISegmentedControl alloc] initWithItems:i == 0 ? @[@"Touch stick", @"External controller"] : @[@"Right hand", @"Left hand", @"Compact"]];
            c.selectedSegmentIndex = i == 0 ? (self.mode == 2 ? 1 : 0) : self.layout; c.backgroundColor = UIColor.lightGrayColor; control = c;
        } else {
            UISwitch *c = [UISwitch new]; c.on = i == 2 ? self.stats : i == 3 ? self.autoHide : self.gameplay; control = c;
        }
        control.tag = i < 2 ? 100 + i : 101 + i; [control addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; [stack addArrangedSubview:control];
    }
    UILabel *rateLabel = [UILabel new]; rateLabel.text = @"Frame rate"; rateLabel.textColor = UIColor.whiteColor; [stack addArrangedSubview:rateLabel];
    UISegmentedControl *rate = [[UISegmentedControl alloc] initWithItems:@[@"60 FPS", @"120 FPS"]];
    rate.selectedSegmentIndex = ShimTargetFPS() == 120 ? 1 : 0; rate.backgroundColor = UIColor.lightGrayColor; rate.tag = 106;
    [rate setEnabled:UIScreen.mainScreen.maximumFramesPerSecond >= 120 forSegmentAtIndex:1];
    [rate addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; [stack addArrangedSubview:rate];
    UILabel *rateHint = [UILabel new]; rateHint.numberOfLines = 0; rateHint.textColor = UIColor.lightGrayColor;
    rateHint.text = @"60 FPS is the default. 120 FPS requests a higher frame rate; actual FPS depends on the game, temperature and power settings."; [stack addArrangedSubview:rateHint];
    UILabel *hint = [UILabel new]; hint.numberOfLines = 0; hint.textColor = UIColor.lightGrayColor;
    hint.text = @"16:9 display • no cropping or stretching. PS5: left stick / D-pad moves, × dashes and accepts, ○ goes back, Options pauses. △ opens game options. Tap the hidden top-left Options spot to reopen this panel."; [stack addArrangedSubview:hint];
    self.uiRate = [UILabel new]; self.uiRate.text = @"Measuring interface refresh…"; self.uiRate.textColor = UIColor.lightGrayColor; self.uiRate.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]; [stack addArrangedSubview:self.uiRate];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"Done" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:close];
}
- (void)dealloc { [self.displayLink invalidate]; [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
__attribute__((constructor)) static void JSBInstallTouchControls(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        __block NSUInteger attempts = 0;
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (!w.isKeyWindow || !w.rootViewController.view) continue;
                    UIView *root = w.rootViewController.view; root.clipsToBounds = YES;
                    [root addSubview:[[JSBTouchOverlay alloc] initWithFrame:root.bounds]];
                    NSLog(@"SHIM JSAB configurable controls installed"); [timer invalidate]; return;
                }
            }
            if (++attempts > 30) [timer invalidate];
        }];
    });
}
