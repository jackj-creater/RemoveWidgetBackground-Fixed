#import <Foundation/Foundation.h>

// Each RBLayer display owns its flags/counters. Nested displays must neither
// inherit another layer's rectangle position nor erase its parent's state.
static NSArray<NSString *> *RWBDrawingStateKeys(void) {
    return @[@"rwb_shouldHideBackground", @"rwb_didSkipFirst", @"rwb_didSkipFirstN"];
}

static NSDictionary *RWBPushDrawingState(NSMutableDictionary *threadDictionary, BOOL enabled) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithCapacity:3];
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
