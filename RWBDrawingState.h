#import <Foundation/Foundation.h>

// Each RBLayer display owns its flags/counters. Nested displays must neither
// inherit another layer's rectangle position nor erase its parent's state.
static NSArray<NSString *> *RWBDrawingStateKeys(void) {
    return @[@"rwb_shouldHideBackground", @"rwb_didSkipFirst", @"rwb_didSkipFirstN",
             @"rwb_largeRectCount", @"rwb_dropFirstLargeRect"];
}

static BOOL RWBShouldSuppressIOS17LargeRect(NSMutableDictionary *threadDictionary) {
    NSUInteger index = [threadDictionary[@"rwb_largeRectCount"] unsignedIntegerValue];
    threadDictionary[@"rwb_largeRectCount"] = @(index + 1);

    NSNumber *firstN = threadDictionary[@"rwb_didSkipFirstN"];
    BOOL suppress = [firstN intValue] > 1;
    if (!suppress) {
        int newN = firstN ? firstN.intValue + 1 : 0;
        threadDictionary[@"rwb_didSkipFirstN"] = @(newN);
        suppress = newN == 1;
    }

    // A repeated two-rectangle display is the iOS 17 refresh form observed on
    // the affected Weather/Fitness host. Its first full-size rect is the only
    // large rect left visible by the original heuristic.
    if (index == 0 && [threadDictionary[@"rwb_dropFirstLargeRect"] boolValue])
        suppress = YES;
    return suppress;
}

static BOOL RWBShouldUseStableDisplayList(NSUInteger largeRectCount,
                                          BOOL hasStableDisplayList) {
    return largeRectCount == 2 && hasStableDisplayList;
}

static BOOL RWBShouldCacheDisplayList(NSUInteger largeRectCount,
                                      BOOL hasDisplayList) {
    return largeRectCount >= 4 && hasDisplayList;
}

static NSDictionary *RWBPushDrawingState(NSMutableDictionary *threadDictionary, BOOL enabled) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithCapacity:5];
    for (NSString *key in RWBDrawingStateKeys()) {
        id value = threadDictionary[key];
        if (value) saved[key] = value;
        [threadDictionary removeObjectForKey:key];
    }
    if (enabled) threadDictionary[@"rwb_shouldHideBackground"] = @YES;
    return saved;
}

static void RWBPopDrawingState(NSMutableDictionary *threadDictionary, NSDictionary *saved) {
    for (NSString *key in RWBDrawingStateKeys()) [threadDictionary removeObjectForKey:key];
    [threadDictionary addEntriesFromDictionary:saved];
}
