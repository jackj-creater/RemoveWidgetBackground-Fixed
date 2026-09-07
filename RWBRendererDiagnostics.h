#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <notify.h>
#import <unistd.h>

static NSString *const RWBRendererDiagnosticPrefix = @"RemoveWidgetBackground-renderer-";
static NSMutableString *RWBRendererDiagnosticReport;
static NSObject *RWBRendererDiagnosticLock;
static NSString *RWBRendererDiagnosticPath;
static NSTimeInterval RWBRendererDiagnosticStarted;
static NSTimeInterval RWBRendererDiagnosticDeadline;
static NSTimeInterval RWBRendererDiagnosticLastWrite;
static NSString *RWBRendererDiagnosticLastSignature;
static NSTimeInterval RWBRendererDiagnosticLastSignatureTime;
static BOOL RWBRendererDiagnosticActive;
static NSUInteger RWBRendererDiagnosticGeneration;
static const NSUInteger RWBRendererDiagnosticLimit = 256 * 1024;
static NSString *const RWBRendererDiagnosticFrameKey = @"rwb_rendererDiagnosticFrame";
static int RWBRendererDiagnosticStateToken = -1;
static uint16_t RWBRendererDiagnosticStateSequence;

static const char *RWBRendererDiagnosticStateChannel(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if ([bundle isEqualToString:@"com.apple.chronod"])
        return "com.82flex.removewidgetbg/drawing-state-chronod";
    if ([bundle isEqualToString:@"com.apple.chrono.WidgetRenderer-CarPlay"])
        return "com.82flex.removewidgetbg/drawing-state-carplay";
    return "com.82flex.removewidgetbg/drawing-state-renderer";
}

static void RWBRendererDiagnosticPublishState(uint64_t state) {
    const char *channel = RWBRendererDiagnosticStateChannel();
    if (RWBRendererDiagnosticStateToken < 0)
        notify_register_check(channel, &RWBRendererDiagnosticStateToken);
    if (RWBRendererDiagnosticStateToken >= 0) {
        notify_set_state(RWBRendererDiagnosticStateToken, state);
        notify_post(channel);
    }
}

static BOOL RWBRendererDiagnosticWriteLocked(void) {
    if (!RWBRendererDiagnosticPath || !RWBRendererDiagnosticReport) return NO;
    return [RWBRendererDiagnosticReport writeToFile:RWBRendererDiagnosticPath atomically:YES
                                           encoding:NSUTF8StringEncoding error:nil];
}

static void RWBRendererDiagnosticAppend(NSString *line) {
    if (!RWBRendererDiagnosticActive || !line) return;
    @synchronized (RWBRendererDiagnosticLock) {
        if (!RWBRendererDiagnosticActive || RWBRendererDiagnosticReport.length >= RWBRendererDiagnosticLimit) return;
        NSString *entry = [NSString stringWithFormat:@"+%.3fs %@\n",
            NSProcessInfo.processInfo.systemUptime - RWBRendererDiagnosticStarted, line];
        NSUInteger room = RWBRendererDiagnosticLimit - RWBRendererDiagnosticReport.length;
        [RWBRendererDiagnosticReport appendString:entry.length <= room ? entry : [entry substringToIndex:room]];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (now - RWBRendererDiagnosticLastWrite >= 1.0) {
            RWBRendererDiagnosticLastWrite = now;
            RWBRendererDiagnosticWriteLocked();
        }
    }
}

static void RWBRendererDiagnosticPostStatus(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name,
                                         NULL, NULL, YES);
}

static void RWBRendererDiagnosticFinish(NSUInteger generation) {
    @synchronized (RWBRendererDiagnosticLock) {
        if (!RWBRendererDiagnosticActive || generation != RWBRendererDiagnosticGeneration) return;
        [RWBRendererDiagnosticReport appendString:@"\nRenderer capture complete.\n"];
        RWBRendererDiagnosticActive = NO;
        RWBRendererDiagnosticWriteLocked();
    }
}

static void RWBRendererDiagnosticBegin(NSTimeInterval deadline) {
    NSTimeInterval nowWall = NSDate.date.timeIntervalSince1970;
    if (deadline <= nowWall) return;
    @synchronized (RWBRendererDiagnosticLock ?: (RWBRendererDiagnosticLock = [NSObject new])) {
        RWBRendererDiagnosticGeneration++;
        RWBRendererDiagnosticStarted = NSProcessInfo.processInfo.systemUptime;
        RWBRendererDiagnosticDeadline = deadline;
        RWBRendererDiagnosticLastWrite = 0;
        RWBRendererDiagnosticLastSignature = nil;
        RWBRendererDiagnosticLastSignatureTime = 0;
        RWBRendererDiagnosticReport = [NSMutableString stringWithFormat:
            @"RemoveWidgetBackground 2.1.3~diagnostic4 drawing process\n%@\nOS %@\nbundle=%@ pid=%d\n"
             "Records drawing dimensions/decisions only; no text, images, pixels, or display-list contents.\n",
            NSDate.date, NSProcessInfo.processInfo.operatingSystemVersionString,
            NSBundle.mainBundle.bundleIdentifier ?: @"unknown", getpid()];
        RWBRendererDiagnosticPath = nil;
        NSString *name = [NSString stringWithFormat:@"%@%d.txt", RWBRendererDiagnosticPrefix, getpid()];
        for (NSString *directory in @[@"/var/mobile/Library/Logs", @"/var/mobile/Library/Preferences"]) {
            NSString *candidate = [directory stringByAppendingPathComponent:name];
            if ([RWBRendererDiagnosticReport writeToFile:candidate atomically:YES
                                                encoding:NSUTF8StringEncoding error:nil]) {
                RWBRendererDiagnosticPath = candidate;
                break;
            }
        }
        BOOL hasWritableReport = RWBRendererDiagnosticPath != nil;
        RWBRendererDiagnosticActive = YES;
        RWBRendererDiagnosticStateSequence = 0;
        RWBRendererDiagnosticPublishState(UINT64_C(1) << 63);
        RWBRendererDiagnosticPostStatus(hasWritableReport
            ? CFSTR("com.82flex.removewidgetbg/renderer-capture-started")
            : CFSTR("com.82flex.removewidgetbg/renderer-capture-write-failed"));
        NSUInteger generation = RWBRendererDiagnosticGeneration;
        NSTimeInterval delay = MAX(0.1, deadline - nowWall);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ RWBRendererDiagnosticFinish(generation); });
    }
}

static void RWBRendererDiagnosticMaybeBegin(NSTimeInterval deadline) {
    if (deadline <= NSDate.date.timeIntervalSince1970) return;
    if (RWBRendererDiagnosticActive && deadline == RWBRendererDiagnosticDeadline) return;
    RWBRendererDiagnosticBegin(deadline);
}

static void RWBRendererDiagnosticDarwinBegin(CFNotificationCenterRef center, void *observer,
                                              CFStringRef name, const void *object,
                                              CFDictionaryRef userInfo) {
    ReloadPrefs();
    NSTimeInterval deadline = kDiagnosticUntil;
    NSUserDefaults *prefs = [[NSUserDefaults alloc]
        initWithSuiteName:@"/var/mobile/Library/Preferences/com.82flex.removewidgetbgprefs.plist"];
    [prefs synchronize];
    deadline = MAX(deadline, [prefs doubleForKey:@"DiagnosticUntil"]);
    RWBRendererDiagnosticMaybeBegin(deadline);
}

static NSMutableDictionary *RWBRendererDiagnosticPushFrame(RBLayer *layer, UIView *view,
                                                            UIWindow *window, BOOL sceneTarget,
                                                            BOOL cachedTarget, BOOL effectiveTarget) {
    if (!RWBRendererDiagnosticActive) return nil;
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSMutableDictionary *frame = [@{
        @"parent": thread[RWBRendererDiagnosticFrameKey] ?: NSNull.null,
        @"layer": NSStringFromClass(layer.class) ?: @"?",
        @"delegate": view ? (NSStringFromClass(view.class) ?: @"?") : @"nil",
        @"scene": window.windowScene ? (NSStringFromClass(window.windowScene.class) ?: @"?") : @"nil",
        @"sceneTarget": @(sceneTarget), @"cachedTarget": @(cachedTarget),
        @"effectiveTarget": @(effectiveTarget), @"opaqueBefore": @(layer.opaque),
        @"large": [NSMutableArray array], @"largeCount": @0,
        @"keptMask": @0, @"sizeHash": @2166136261U
    } mutableCopy];
    NSString *widgetID = nil;
    if ([window.windowScene respondsToSelector:@selector(widget)]) {
        CHSWidget *widget = [(id)window.windowScene widget];
        widgetID = widget.extensionBundleIdentifier;
    }
    frame[@"widget"] = widgetID ?: @"nil";
    thread[RWBRendererDiagnosticFrameKey] = frame;
    return frame;
}

static void RWBRendererDiagnosticRecordRect(CGRect rect, BOOL isLarge, BOOL suppressed) {
    if (!RWBRendererDiagnosticActive || !isLarge) return;
    NSMutableDictionary *frame = NSThread.currentThread.threadDictionary[RWBRendererDiagnosticFrameKey];
    if (!frame) return;
    NSUInteger count = [frame[@"largeCount"] unsignedIntegerValue];
    frame[@"largeCount"] = @(MIN(count + 1, 31));
    if (!suppressed && count < 16)
        frame[@"keptMask"] = @([frame[@"keptMask"] unsignedIntValue] | (1U << count));
    uint32_t hash = [frame[@"sizeHash"] unsignedIntValue];
    int32_t values[] = {(int32_t)lrint(rect.origin.x * 2), (int32_t)lrint(rect.origin.y * 2),
                        (int32_t)lrint(rect.size.width * 2), (int32_t)lrint(rect.size.height * 2)};
    for (NSUInteger i = 0; i < 4; i++) hash = (hash ^ (uint32_t)values[i]) * 16777619U;
    frame[@"sizeHash"] = @(hash);
    NSMutableArray *large = frame[@"large"];
    if (!large || large.count >= 16) return;
    [large addObject:[NSString stringWithFormat:@"%lu:%@:%@",
        (unsigned long)large.count + 1, suppressed ? @"drop" : @"keep", NSStringFromCGRect(rect)]];
}

static void RWBRendererDiagnosticPopFrame(NSMutableDictionary *frame, RBLayer *layer) {
    if (!frame) return;
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    id parent = frame[@"parent"];
    if (parent == NSNull.null) [thread removeObjectForKey:RWBRendererDiagnosticFrameKey];
    else thread[RWBRendererDiagnosticFrameKey] = parent;
    NSArray *large = frame[@"large"];
    if (!large.count && ![frame[@"effectiveTarget"] boolValue]) return;
    uint64_t compact = UINT64_C(1) << 63;
    compact |= (uint64_t)([frame[@"sceneTarget"] boolValue] ? 1 : 0) << 62;
    compact |= (uint64_t)([frame[@"cachedTarget"] boolValue] ? 1 : 0) << 61;
    compact |= (uint64_t)([frame[@"effectiveTarget"] boolValue] ? 1 : 0) << 60;
    compact |= (uint64_t)([frame[@"opaqueBefore"] boolValue] ? 1 : 0) << 59;
    compact |= (uint64_t)(layer.opaque ? 1 : 0) << 58;
    compact |= (uint64_t)(++RWBRendererDiagnosticStateSequence & 0xFFF) << 46;
    compact |= (uint64_t)([frame[@"largeCount"] unsignedIntegerValue] & 0x1F) << 41;
    compact |= (uint64_t)([frame[@"keptMask"] unsignedIntValue] & 0xFFFF) << 25;
    compact |= (uint64_t)([frame[@"sizeHash"] unsignedIntValue] & 0xFFFF) << 9;
    RWBRendererDiagnosticPublishState(compact);
    NSString *signature = [NSString stringWithFormat:
        @"layer=%@ delegate=%@ scene=%@ widget=%@ sceneTarget=%d cachedTarget=%d target=%d opaque=%d->%d large=[%@]",
        frame[@"layer"], frame[@"delegate"], frame[@"scene"], frame[@"widget"],
        [frame[@"sceneTarget"] boolValue], [frame[@"cachedTarget"] boolValue],
        [frame[@"effectiveTarget"] boolValue], [frame[@"opaqueBefore"] boolValue], layer.opaque,
        [large componentsJoinedByString:@"; "]];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (RWBRendererDiagnosticLock) {
        if ([signature isEqualToString:RWBRendererDiagnosticLastSignature] &&
            now - RWBRendererDiagnosticLastSignatureTime < 0.25) return;
        RWBRendererDiagnosticLastSignature = signature;
        RWBRendererDiagnosticLastSignatureTime = now;
    }
    RWBRendererDiagnosticAppend(signature);
}
