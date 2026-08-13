#import <UIKit/UIKit.h>
#import <objc/message.h>

#import <HBLog.h>

static BOOL kIsEnabled = YES;
static BOOL kIsEnabledForSystemWidgets = YES;
static BOOL kIsEnabledForMaterialView = YES;

static BOOL kForceDarkMode = NO;

static CGFloat kMaxWidgetWidth = 150;
static CGFloat kMaxWidgetHeight = 150;
static NSSet<NSString *> *kWidgetBundleIdentifiers = nil;

static void ReloadPrefs() {
    static NSUserDefaults *prefs = nil;
    if (!prefs) {
        prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.removewidgetbgprefs"];
    }

    NSDictionary *settings = [prefs dictionaryRepresentation];

    if (settings[@"IsEnabled"]) {
        kIsEnabled = [settings[@"IsEnabled"] boolValue];
    } else {
        kIsEnabled = YES;
    }

    if (settings[@"IsSystemWidgetsEnabled"]) {
        kIsEnabledForSystemWidgets = [settings[@"IsSystemWidgetsEnabled"] boolValue];
    } else {
        kIsEnabledForSystemWidgets = YES;
    }

    if (settings[@"IsMaterialViewEnabled"]) {
        kIsEnabledForMaterialView = [settings[@"IsMaterialViewEnabled"] boolValue];
    } else {
        kIsEnabledForMaterialView = YES;
    }

    if (settings[@"ForceDarkMode"]) {
        kForceDarkMode = [settings[@"ForceDarkMode"] boolValue];
    } else {
        // WidgetRenderer may not be able to read the shared preference domain
        // on every jailbreak setup. Never fall back to an unexpected dark mode.
        kForceDarkMode = NO;
    }

    if (settings[@"MaxWidgetWidth"]) {
        kMaxWidgetWidth = [settings[@"MaxWidgetWidth"] floatValue];
    } else {
        kMaxWidgetWidth = 150;
    }

    if (settings[@"MaxWidgetHeight"]) {
        kMaxWidgetHeight = [settings[@"MaxWidgetHeight"] floatValue];
    } else {
        kMaxWidgetHeight = 150;
    }

    if (settings[@"WidgetBundleIdentifiers"]) {
        kWidgetBundleIdentifiers = [NSSet setWithArray:settings[@"WidgetBundleIdentifiers"]];
    } else {
        kWidgetBundleIdentifiers = [NSSet setWithArray:@[
            @"com.growing.topwidgetsplus.Widget", // Top Widgets
            @"dk.simonbs.Scriptable.ScriptableWidget", // Scriptable
            @"wiki.qaq.trapp.LaunchPad", // ?????
        ]];
    }

    if (kIsEnabledForSystemWidgets) {
        NSArray<NSString *> *kSystemWidgetBundleIdentifiers = @[
            @"com.apple.mobiletimer.WorldClockWidget", // ??
            @"com.apple.mobilecal.CalendarWidgetExtension", // ??
            @"com.apple.mobilemail.MailWidgetExtension", // ??
            @"com.apple.ScreenTimeWidgetApplication.ScreenTimeWidgetExtension", // ????
            @"com.apple.reminders.WidgetExtension", // ????
            @"com.apple.weather.widget", // ??
            @"com.apple.Fitness.FitnessWidget", // ??
            @"com.apple.Passbook.PassbookWidgets", // ??
            @"com.apple.Health.Sleep.SleepWidgetExtension", // ??
            @"com.apple.tips.TipsSwift", // ??
            @"com.apple.Music.MusicWidgets", // ??
            @"com.apple.gamecenter.widgets.extension", // Game Center
            @"com.apple.tv.TVWidgetExtension", // TV
            @"com.apple.news.widget", // Apple News
        ];
        kWidgetBundleIdentifiers = [kWidgetBundleIdentifiers setByAddingObjectsFromArray:kSystemWidgetBundleIdentifiers];
    }

    HBLogDebug(@"ReloadPrefs: isEnabled=%d, isEnabledForSystemWidgets=%d, isEnabledForMaterialView=%d, "
               @"forceDarkMode=%d, maxWidgetWidth=%.1f, maxWidgetHeight=%.1f, widgetBundleIdentifiers=%@",
               kIsEnabled, kIsEnabledForSystemWidgets, kIsEnabledForMaterialView, kForceDarkMode, kMaxWidgetWidth,
               kMaxWidgetHeight, kWidgetBundleIdentifiers);
}

@interface CHSWidget : NSObject
@property (nonatomic, copy, readonly) NSString *extensionBundleIdentifier;
@end

@interface CHUISWidgetScene : UIWindowScene
@property (nonatomic, copy, readonly) CHSWidget *widget;
@end

@interface CHUISAvocadoWindowScene : UIWindowScene
@property (nonatomic, copy, readonly) CHSWidget *widget;
@end

@interface UIWindow (RWB)
@property (nonatomic, strong) NSNumber *rwb_shouldHideBackground;
@end

@interface RBLayer : CALayer
@end

@interface RBDisplayList : NSObject
- (id)xmlDescription;
@end

@interface SBHWidgetViewController : UIViewController
@end

@interface CHUISWidgetHostViewController : UIViewController
@property (nonatomic, copy) CHSWidget *widget;
@property (nonatomic) BOOL drawSystemBackgroundMaterialIfNecessary;
- (void)_setBackgroundViewMode:(int)mode;
@end

@interface SBHWidgetStackViewController : UIViewController
@end

@interface WGWidgetListItemViewController : UIViewController
@end

@interface SBIcon : NSObject
@end

@interface SBIconView : NSObject
@property (nonatomic, strong) SBIcon *icon;
@end

@interface CHUISAvocadoHostViewController : UIViewController
@property (nonatomic, copy) CHSWidget *widget;
@end

static BOOL RWBShouldHideBackgroundForWidget(CHSWidget *widget) {
    return [widget isKindOfClass:%c(CHSWidget)] &&
           widget.extensionBundleIdentifier &&
           [kWidgetBundleIdentifiers containsObject:widget.extensionBundleIdentifier];
}

static BOOL RWBShouldHideBackgroundForScene(UIWindowScene *scene) {
    if (![scene respondsToSelector:@selector(widget)]) {
        return NO;
    }

    CHSWidget *widget = [(id)scene widget];
    return RWBShouldHideBackgroundForWidget(widget);
}

// On iOS 17 the scene can be attached to its window before the widget metadata
// is available. Re-check it at render/layout time so the very first valid frame
// is transparent instead of briefly using the renderer's opaque black surface.
static BOOL RWBRefreshWindowTarget(UIWindow *window) {
    if (!window) {
        return NO;
    }

    BOOL shouldHide = window.rwb_shouldHideBackground.boolValue ||
                      RWBShouldHideBackgroundForScene(window.windowScene);
    window.rwb_shouldHideBackground = @(shouldHide);

    if (shouldHide) {
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        window.layer.opaque = NO;
    }

    return shouldHide;
}

static void RWBHideMaterialViewsInHierarchy(UIView *view) {
    if (!view) {
        return;
    }

    Class materialViewClass = %c(MTMaterialView);
    NSString *className = NSStringFromClass(view.class);
    if ((materialViewClass && [view isKindOfClass:materialViewClass]) ||
        [className containsString:@"MaterialView"])
    {
        view.alpha = 0;
        return;
    }

    for (UIView *subview in view.subviews) {
        RWBHideMaterialViewsInHierarchy(subview);
    }
}

static void RWBUpdateWidgetChrome(UIViewController *viewController) {
    if (!kIsEnabledForMaterialView || !viewController.isViewLoaded) {
        return;
    }

    UIView *rootView = viewController.view;
    rootView.backgroundColor = UIColor.clearColor;
    rootView.opaque = NO;
    rootView.layer.opaque = NO;

    UIView *firstChild = rootView.subviews.firstObject;
    if ([firstChild isKindOfClass:UIVisualEffectView.class]) {
        firstChild.alpha = 0;
    }

    // iOS 17 adds extra container views in Today View (the leftmost page),
    // so the material view is no longer guaranteed to be the first child.
    RWBHideMaterialViewsInHierarchy(rootView);
}

static BOOL RWBShouldSuppressHostBackground(CHUISWidgetHostViewController *viewController) {
    return RWBShouldHideBackgroundForWidget(viewController.widget);
}

static void RWBEnforceHostTransparency(CHUISWidgetHostViewController *viewController) {
    if (!RWBShouldSuppressHostBackground(viewController)) {
        return;
    }

    viewController.drawSystemBackgroundMaterialIfNecessary = NO;
    if ([viewController respondsToSelector:@selector(_setBackgroundViewMode:)]) {
        ((void (*)(id, SEL, int))objc_msgSend)(viewController, @selector(_setBackgroundViewMode:), 0);
    }
    RWBUpdateWidgetChrome(viewController);
}

%group RWBSpringBoard

%hook CHUISAvocadoHostViewController

/* iOS 15 */
- (void)_updateBackgroundMaterialAndColor {
    CHSWidget *widget = self.widget;
    if ([widget isKindOfClass:%c(CHSWidget)] &&
        widget.extensionBundleIdentifier &&
        [kWidgetBundleIdentifiers containsObject:widget.extensionBundleIdentifier])
    {
        return;
    }
    %orig;
}

/* iOS 15 */
- (id)screenshotManager {
    CHSWidget *widget = self.widget;
    if ([widget isKindOfClass:%c(CHSWidget)] &&
        widget.extensionBundleIdentifier &&
        [kWidgetBundleIdentifiers containsObject:widget.extensionBundleIdentifier])
    {
        return nil;
    }
    return %orig;
}

%end

%hook SBHWidgetViewController

- (void)viewDidLoad {
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillAppear:(BOOL)arg1 {
    RWBUpdateWidgetChrome(self);
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillLayoutSubviews {
    RWBUpdateWidgetChrome(self);
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    RWBUpdateWidgetChrome(self);
}

%end

%hook CHUISWidgetHostViewController

// iOS 17 calls this again when SpringBoard restores widgets after unlocking.
// Mode 1 creates an opaque color view (black in dark appearance), while mode 0
// hides it. Intercept the mode change before the black frame can be committed.
- (void)_setBackgroundViewMode:(int)mode {
    if (RWBShouldSuppressHostBackground(self)) {
        %orig(0);
        RWBUpdateWidgetChrome(self);
        return;
    }

    %orig(mode);
}

- (int)_expectedBackgroundViewMode {
    if (RWBShouldSuppressHostBackground(self)) {
        return 0;
    }

    return %orig;
}

- (BOOL)drawSystemBackgroundMaterialIfNecessary {
    if (RWBShouldSuppressHostBackground(self)) {
        return NO;
    }

    return %orig;
}

- (void)setDrawSystemBackgroundMaterialIfNecessary:(BOOL)shouldDraw {
    if (RWBShouldSuppressHostBackground(self)) {
        %orig(NO);
        return;
    }

    %orig(shouldDraw);
}

- (BOOL)usesSystemBackgroundMaterial {
    if (RWBShouldSuppressHostBackground(self)) {
        return NO;
    }

    return %orig;
}

- (void)setWidget:(CHSWidget *)widget {
    %orig;

    if (RWBShouldHideBackgroundForWidget(widget)) {
        RWBEnforceHostTransparency(self);

        // Some iOS 17 hosts install their material view immediately after the
        // widget setter returns. Clean once more on the next main-loop turn.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (RWBShouldHideBackgroundForWidget(self.widget)) {
                RWBEnforceHostTransparency(self);
            }
        });
    }
}

- (void)viewDidLoad {
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillAppear:(BOOL)arg1 {
    RWBEnforceHostTransparency(self);
    %orig;
    RWBEnforceHostTransparency(self);
}

- (void)viewDidMoveToWindow:(UIWindow *)window shouldAppearOrDisappear:(BOOL)shouldAppearOrDisappear {
    RWBEnforceHostTransparency(self);
    %orig;
    RWBEnforceHostTransparency(self);
}

- (void)viewWillLayoutSubviews {
    RWBUpdateWidgetChrome(self);
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (unsigned long long)colorScheme {
    return kForceDarkMode ? 2 : 1;
}

- (void)_updateBackgroundMaterialAndColor {
    CHSWidget *widget = self.widget;
    if ([widget isKindOfClass:%c(CHSWidget)] &&
        widget.extensionBundleIdentifier &&
        [kWidgetBundleIdentifiers containsObject:widget.extensionBundleIdentifier])
    {
        RWBUpdateWidgetChrome(self);
        return;
    }
    %orig;
}

- (void)_updatePersistedSnapshotContent {
    RWBEnforceHostTransparency(self);
    %orig;
    RWBEnforceHostTransparency(self);
}

- (void)_updatePersistedSnapshotContentIfNecessary {
    RWBEnforceHostTransparency(self);
    %orig;
    RWBEnforceHostTransparency(self);
}

- (void)_ensureAndEvaluateSnapshotView {
    RWBEnforceHostTransparency(self);
    %orig;
    RWBEnforceHostTransparency(self);
}

- (void)_applyLiveSnapshotContentsFromSnapshot:(id)snapshot {
    RWBEnforceHostTransparency(self);
    %orig(snapshot);
    RWBEnforceHostTransparency(self);
}

- (void)sceneContentStateDidChange:(id)scene {
    RWBEnforceHostTransparency(self);
    %orig(scene);
    RWBEnforceHostTransparency(self);
}

- (void)sceneLayerManagerDidUpdateLayers:(id)layerManager {
    RWBEnforceHostTransparency(self);
    %orig(layerManager);
    RWBEnforceHostTransparency(self);
}

/* iOS 16.0 to 16.2 */
- (id)_snapshotImageFromURL:(id)arg1 {
    CHSWidget *widget = self.widget;
    if ([widget isKindOfClass:%c(CHSWidget)] &&
        widget.extensionBundleIdentifier &&
        [kWidgetBundleIdentifiers containsObject:widget.extensionBundleIdentifier])
    {
        return nil;
    }
    return %orig;
}

%end

%hook SBIconView

- (double)iconLabelAlpha {
    if (self.icon && [self.icon isKindOfClass:%c(SBWidgetIcon)]) {
        return 0;
    }
    return %orig;
}

- (double)effectiveIconLabelAlpha {
    if (self.icon && [self.icon isKindOfClass:%c(SBWidgetIcon)]) {
        return 0;
    }
    return %orig;
}

%end

%hook SBHWidgetStackViewController

- (void)viewDidLoad {
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillAppear:(BOOL)arg1 {
    RWBUpdateWidgetChrome(self);
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillLayoutSubviews {
    RWBUpdateWidgetChrome(self);
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    RWBUpdateWidgetChrome(self);
}

%end

%hook WGWidgetListItemViewController

- (void)viewDidLoad {
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillAppear:(BOOL)arg1 {
    RWBUpdateWidgetChrome(self);
    %orig;
    RWBUpdateWidgetChrome(self);
}

- (void)viewWillLayoutSubviews {
    RWBUpdateWidgetChrome(self);
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    RWBUpdateWidgetChrome(self);
}

%end

%end

%group RWB

%hook UIWindow

%property (nonatomic, strong) NSNumber *rwb_shouldHideBackground;

- (UIWindow *)initWithWindowScene:(UIWindowScene *)scene {
    UIWindow *window = %orig;
    if (window) {
        window.rwb_shouldHideBackground = @(RWBShouldHideBackgroundForScene(scene));
        RWBRefreshWindowTarget(window);
        window.overrideUserInterfaceStyle = kForceDarkMode
                                                ? UIUserInterfaceStyleDark
                                                : UIUserInterfaceStyleLight;
    }
    return window;
}

%end

%hook CHUISWidgetScene

- (unsigned long long)colorScheme {
    return kForceDarkMode ? 2 : 1;
}

%end

%hook CHSMutableScreenshotPresentationAttributes

- (long long)colorScheme {
    return kForceDarkMode ? 2 : 1;
}

%end

%hook CHSScreenshotPresentationAttributes

- (long long)colorScheme {
    return kForceDarkMode ? 2 : 1;
}

%end

%hook UIView

- (void)layoutSubviews {
    UIWindow *window = self.window;
    BOOL shouldHideBackground = RWBRefreshWindowTarget(window);

    if (shouldHideBackground &&
        ![NSStringFromClass([self class]) containsString:@"UIHostingView"])
    {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.layer.opaque = NO;
    }

    %orig;

    // UIKit can restore a container background during layout, so enforce the
    // transparent state on both sides of the first layout pass.
    if (shouldHideBackground &&
        ![NSStringFromClass([self class]) containsString:@"UIHostingView"])
    {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.layer.opaque = NO;
    }
}

%end

%hook RBLayer

- (void)display {
    UIView *view = (UIView *)self.delegate;
    UIWindow *window = [view isKindOfClass:[UIView class]] ? view.window : nil;

    if ([view isKindOfClass:[UIView class]] && RWBRefreshWindowTarget(window)) {
        [NSThread currentThread].threadDictionary[@"rwb_shouldHideBackground"] = @YES;
        if (@available(iOS 17, *)) {
            if (self.opaque)
                self.opaque = NO;
        }

        %orig;

        [NSThread currentThread].threadDictionary[@"rwb_shouldHideBackground"] = nil;
        if (@available(iOS 17, *)) {
            [NSThread currentThread].threadDictionary[@"rwb_didSkipFirstN"] = nil;
        } else {
            [NSThread currentThread].threadDictionary[@"rwb_didSkipFirst"] = nil;
        }

        return;
    }

    %orig;
}

%end

%end

%group RWB_15

%hook RBShape

- (void)setRect:(CGRect)arg1 {
    if ([NSThread currentThread].threadDictionary[@"rwb_shouldHideBackground"]) {
        if (arg1.size.width > kMaxWidgetWidth && arg1.size.height > kMaxWidgetHeight) {
            %orig(CGRectZero);
            return;
        }
    }
    %orig;
}

%end

%hook UISCurrentUserInterfaceStyleValue

- (long long)userInterfaceStyle {
    return kForceDarkMode ? 2 : 1;
}

%end

%end

%group RWB_16

%hook RBShape

- (void)setRect:(CGRect)arg1 {
    NSMutableDictionary *threadDict = [NSThread currentThread].threadDictionary;
    if (threadDict[@"rwb_shouldHideBackground"]) {
        if (arg1.size.width > kMaxWidgetWidth && arg1.size.height > kMaxWidgetHeight) {
            if ([threadDict[@"rwb_didSkipFirst"] boolValue]) {
                %orig(CGRectZero);
                return;
            }
            threadDict[@"rwb_didSkipFirst"] = @YES;
        }
    }
    %orig;
}

%end

%end

%group RWB_17

%hook RBShape

- (void)setRect:(CGRect)arg1 {
    NSMutableDictionary *threadDict = [NSThread currentThread].threadDictionary;
    if (threadDict[@"rwb_shouldHideBackground"]) {
        if (arg1.size.width > kMaxWidgetWidth && arg1.size.height > kMaxWidgetHeight) {
            NSNumber *firstN = threadDict[@"rwb_didSkipFirstN"];
            if ([firstN intValue] > 1) {
                %orig(CGRectZero);
                return;
            }
            int newN = firstN ? [firstN intValue] + 1 : 0;
            threadDict[@"rwb_didSkipFirstN"] = @(newN);
            if (newN == 1) {
                // Bypass the first background rect
                %orig(CGRectZero);
                return;
            }
        }
    }
    %orig;
}

%end

%end

%ctor {
    ReloadPrefs();
    if (!kIsEnabled) {
        return;
    }

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)ReloadPrefs,
        CFSTR("com.82flex.removewidgetbgprefs/saved"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        HBLogDebug(@"Initialized in SpringBoard");
        %init(RWBSpringBoard);
    }
    else if ([bundleIdentifier isEqualToString:@"com.apple.chronod"] || [bundleIdentifier hasPrefix:@"com.apple.chrono.WidgetRenderer-"]) {
        HBLogDebug(@"Initialized in chronod (or WidgetRenderer)");
        %init(RWB);
        if (@available(iOS 17, *)) {
            %init(RWB_17);
        } else if (@available(iOS 16, *)) {
            %init(RWB_16);
        } else {
            %init(RWB_15);
        }
    }
}
