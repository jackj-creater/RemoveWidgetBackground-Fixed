#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Explicitly started, bounded SpringBoard-only capture. No widget text, images,
// remote scene contents or screenshot pixels are read or exported.
static NSString *const RWBDiagnosticPath = @"/var/mobile/Library/Logs/RemoveWidgetBackground-diagnostic.txt";
static NSHashTable<UIViewController *> *RWBDiagnosticHosts;
static NSMutableString *RWBDiagnosticReport;
static NSMutableDictionary<NSValue *, NSString *> *RWBDiagnosticLastStates;
static NSTimeInterval RWBDiagnosticStarted;
static NSUInteger RWBDiagnosticGeneration;
static BOOL RWBDiagnosticActive;
static const NSUInteger RWBDiagnosticLimit = 192 * 1024;

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
            @"RemoveWidgetBackground 2.1.3~test2\n%@\nOS %@\nRecording; export after 30 seconds.\n",
            NSDate.date, NSProcessInfo.processInfo.operatingSystemVersionString];
        RWBDiagnosticLastStates = [NSMutableDictionary dictionary];
        RWBDiagnosticActive = YES;
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
        RWBDiagnosticSample(RWBDiagnosticGeneration, 0);
    });
}
