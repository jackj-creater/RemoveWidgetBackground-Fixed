#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

// Explicitly started, bounded SpringBoard-only capture. No widget text, images,
// remote scene contents or screenshot pixels are read or exported.
static NSString *const RWBDiagnosticPath = @"/var/mobile/Library/Logs/RemoveWidgetBackground-diagnostic.txt";
static NSHashTable<UIViewController *> *RWBDiagnosticHosts;
static NSMutableString *RWBDiagnosticReport;
static NSMutableDictionary<NSValue *, NSString *> *RWBDiagnosticLastStates;
static NSTimeInterval RWBDiagnosticStarted;
static NSUInteger RWBDiagnosticGeneration;
static BOOL RWBDiagnosticActive;
static const NSUInteger RWBDiagnosticLimit = 512 * 1024;
static int RWBDiagnosticDrawingTokens[3] = {-1, -1, -1};
static uint64_t RWBDiagnosticDrawingLastStates[3];
static const char *RWBDiagnosticDrawingChannels[3] = {
    "com.82flex.removewidgetbg/drawing-state-chronod",
    "com.82flex.removewidgetbg/drawing-state-renderer",
    "com.82flex.removewidgetbg/drawing-state-carplay"
};
static NSString *RWBDiagnosticDrawingNames[3] = {@"chronod", @"renderer", @"carplay"};

static void RWBDiagnosticAppend(NSString *line) {
    if (!RWBDiagnosticActive || RWBDiagnosticReport.length >= RWBDiagnosticLimit) return;
    NSString *entry = [NSString stringWithFormat:@"+%.3fs %@\n",
        NSProcessInfo.processInfo.systemUptime - RWBDiagnosticStarted, line];
    NSUInteger remaining = RWBDiagnosticLimit - RWBDiagnosticReport.length;
    [RWBDiagnosticReport appendString:entry.length <= remaining ? entry : [entry substringToIndex:remaining]];
}

static NSString *RWBDiagnosticColor(CGColorRef color) {
    if (!color) return @"nil";
    const CGFloat *components = CGColorGetComponents(color);
    size_t count = CGColorGetNumberOfComponents(color);
    NSMutableString *result = [NSMutableString stringWithString:@"["];
    for (size_t i = 0; i < MIN(count, 5); i++) [result appendFormat:@"%.2f,", components[i]];
    [result appendString:@"]"];
    return result;
}

static void RWBDiagnosticLayer(CALayer *layer, NSMutableString *output, NSUInteger depth, NSUInteger *budget) {
    if (!layer || !*budget || depth > 8) return;
    --*budget;
    CALayer *presentation = layer.presentationLayer;
    [output appendFormat:@"%*sL %@ hidden=%d opacity=%.2f presented=%.2f opaque=%d bg=%@ contents=%d bounds=%@\n",
        (int)depth, "", NSStringFromClass(layer.class), layer.hidden, layer.opacity,
        presentation ? presentation.opacity : layer.opacity, layer.opaque,
        RWBDiagnosticColor(layer.backgroundColor), layer.contents != nil, NSStringFromCGRect(layer.bounds)];
    for (CALayer *child in layer.sublayers) RWBDiagnosticLayer(child, output, depth + 1, budget);
}

static void RWBDiagnosticView(UIView *view, NSMutableString *output, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 8) return;
    --*budget;
    [output appendFormat:@"%*sV %@ hidden=%d alpha=%.2f opaque=%d bg=%@ bounds=%@\n",
        (int)depth, "", NSStringFromClass(view.class), view.hidden, view.alpha,
        view.opaque, RWBDiagnosticColor(view.backgroundColor.CGColor), NSStringFromCGRect(view.bounds)];
    for (UIView *child in view.subviews) RWBDiagnosticView(child, output, depth + 1, budget);
}

static void RWBDiagnosticTrack(UIViewController *host) {
    if (![NSThread isMainThread]) return;
    if (!RWBDiagnosticHosts) RWBDiagnosticHosts = [NSHashTable weakObjectsHashTable];
    [RWBDiagnosticHosts addObject:host];
}

static void RWBDiagnosticEvent(UIViewController *host, NSString *event) {
    if (![NSThread isMainThread] || !RWBDiagnosticActive) return;
    RWBDiagnosticAppend([NSString stringWithFormat:@"host=%p %@", host, event]);
}

static BOOL RWBDiagnosticWrite(void) {
    NSString *directory = RWBDiagnosticPath.stringByDeletingLastPathComponent;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
              withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    return [RWBDiagnosticReport writeToFile:RWBDiagnosticPath atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil];
}

static void RWBDiagnosticDrawingStatus(CFNotificationCenterRef center, void *observer,
                                       CFStringRef name, const void *object,
                                       CFDictionaryRef userInfo) {
    if (!RWBDiagnosticActive) return;
    NSString *event = [(__bridge NSString *)name hasSuffix:@"write-failed"]
        ? @"drawing process could not write file; compact state channel remains active"
        : @"drawing process capture started";
    dispatch_async(dispatch_get_main_queue(), ^{ RWBDiagnosticAppend(event); });
}

static void RWBDiagnosticPollDrawingStates(NSUInteger generation) {
    if (!RWBDiagnosticActive || generation != RWBDiagnosticGeneration) return;
    for (NSUInteger i = 0; i < 3; i++) {
        uint64_t state = 0;
        if (RWBDiagnosticDrawingTokens[i] >= 0 &&
            notify_get_state(RWBDiagnosticDrawingTokens[i], &state) == NOTIFY_STATUS_OK &&
            state && state != RWBDiagnosticDrawingLastStates[i]) {
            RWBDiagnosticDrawingLastStates[i] = state;
            RWBDiagnosticAppend([NSString stringWithFormat:
                @"drawing-state process=%@ active=%d seq=%lu sceneTarget=%d cachedTarget=%d target=%d "
                 "opaque=%d->%d large=%lu keptMask=0x%04lx sizeHash=0x%04lx contents=%d restored=%d "
                 "listHook=%d listCount2=%d stable=%d substituted=%d encoded=%d decoded=%d replayRects=%d",
                RWBDiagnosticDrawingNames[i], (int)((state >> 63) & 1),
                (unsigned long)((state >> 46) & 0xFFF), (int)((state >> 62) & 1),
                (int)((state >> 61) & 1), (int)((state >> 60) & 1),
                (int)((state >> 59) & 1), (int)((state >> 58) & 1),
                (unsigned long)((state >> 41) & 0x1F),
                (unsigned long)((state >> 25) & 0xFFFF),
                (unsigned long)((state >> 9) & 0xFFFF), (int)((state >> 8) & 1),
                (int)((state >> 7) & 1), (int)((state >> 6) & 1),
                (int)((state >> 3) & 1), (int)((state >> 5) & 1),
                (int)((state >> 4) & 1), (int)((state >> 2) & 1),
                (int)((state >> 1) & 1), (int)(state & 1)]);
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 40), dispatch_get_main_queue(), ^{
        RWBDiagnosticPollDrawingStates(generation);
    });
}

static void RWBDiagnosticSample(NSUInteger generation, NSUInteger tick) {
    if (!RWBDiagnosticActive || generation != RWBDiagnosticGeneration) return;
    NSUInteger count = 0;
    for (UIViewController *host in RWBDiagnosticHosts.allObjects) {
        if (!host.isViewLoaded || ++count > 16) continue;
        UIView *view = host.view;
        NSMutableString *state = [NSMutableString stringWithFormat:@"host=%p class=%@ attached=%d\n",
            host, NSStringFromClass(host.class), view.window != nil];
        NSUInteger budget = 64;
        RWBDiagnosticView(view, state, 0, &budget);
        budget = 64;
        RWBDiagnosticLayer(view.layer, state, 0, &budget);
        // The black chrome can belong to an enclosing SpringBoard container,
        // outside the remote host's own view. Inspect at most three ancestors.
        UIView *container = view;
        for (NSUInteger i = 0; i < 3 && container.superview &&
             ![container.superview isKindOfClass:UIWindow.class]; i++) container = container.superview;
        if (container != view) {
            [state appendString:@"Enclosing container:\n"];
            budget = 64;
            RWBDiagnosticView(container, state, 0, &budget);
            budget = 64;
            RWBDiagnosticLayer(container.layer, state, 0, &budget);
        }
        NSValue *key = [NSValue valueWithNonretainedObject:host];
        if (![RWBDiagnosticLastStates[key] isEqualToString:state]) {
            RWBDiagnosticAppend(state);
            RWBDiagnosticLastStates[key] = state;
        }
    }
    // 60 half-second intervals, then stop. No permanent timer or disk polling.
    if (tick >= 60 || RWBDiagnosticReport.length >= RWBDiagnosticLimit) {
        [RWBDiagnosticReport appendString:@"\nCapture complete (30s or size limit).\n"];
        RWBDiagnosticActive = NO;
        RWBDiagnosticWrite();
        RWBDiagnosticLastStates = nil;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        RWBDiagnosticSample(generation, tick + 1);
    });
}

static void RWBDiagnosticBegin(CFNotificationCenterRef center, void *observer, CFStringRef name,
                               const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RWBDiagnosticGeneration++;
        RWBDiagnosticStarted = NSProcessInfo.processInfo.systemUptime;
        RWBDiagnosticReport = [NSMutableString stringWithFormat:
            @"RemoveWidgetBackground 2.1.3~test11 diagnostic9 SpringBoard\n%@\nOS %@\nRecording; export after 30 seconds.\n",
            NSDate.date, NSProcessInfo.processInfo.operatingSystemVersionString];
        RWBDiagnosticLastStates = [NSMutableDictionary dictionary];
        RWBDiagnosticActive = YES;
        for (NSUInteger i = 0; i < 3; i++) {
            if (RWBDiagnosticDrawingTokens[i] < 0)
                notify_register_check(RWBDiagnosticDrawingChannels[i], &RWBDiagnosticDrawingTokens[i]);
            if (RWBDiagnosticDrawingTokens[i] >= 0)
                notify_set_state(RWBDiagnosticDrawingTokens[i], 0);
            RWBDiagnosticDrawingLastStates[i] = 0;
        }
        for (NSString *className in @[@"CHUISWidgetHostViewController", @"SBHWidgetContainerView"]) {
            Class cls = NSClassFromString(className);
            for (NSString *selector in @[@"_setBackgroundViewMode:", @"_expectedBackgroundViewMode",
                     @"_updatePersistedSnapshotContent", @"backgroundView"]) {
                Method method = class_getInstanceMethod(cls, NSSelectorFromString(selector));
                RWBDiagnosticAppend([NSString stringWithFormat:@"method %@ %@ exists=%d encoding=%s",
                    className, selector, method != NULL, method ? method_getTypeEncoding(method) : "-"]);
            }
        }
        // The status file lets Settings distinguish a missing SpringBoard hook
        // from a successfully started capture; the full report is written once.
        if (!RWBDiagnosticWrite()) { RWBDiagnosticActive = NO; return; }
        RWBDiagnosticPollDrawingStates(RWBDiagnosticGeneration);
        RWBDiagnosticSample(RWBDiagnosticGeneration, 0);
    });
}
