#import "../RWBDrawingState.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObject:@"untouched" forKey:@"other"];
        NSDictionary *original = [state copy];
        NSDictionary *outer = RWBPushDrawingState(state, YES);
        assert([state[@"rwb_shouldHideBackground"] boolValue]);
        assert(!state[@"rwb_didSkipFirstN"]);
        state[@"rwb_didSkipFirstN"] = @2;
        state[@"rwb_didSkipFirst"] = @YES;
        NSDictionary *parent = [state copy];

        // Target child begins at its own first rect, then restores the parent.
        NSDictionary *child = RWBPushDrawingState(state, YES);
        assert([state[@"rwb_shouldHideBackground"] boolValue]);
        assert(!state[@"rwb_didSkipFirstN"] && !state[@"rwb_didSkipFirst"]);
        state[@"rwb_didSkipFirstN"] = @7;
        RWBPopDrawingState(state, child);
        assert([state isEqualToDictionary:parent]);

        // Non-target child must not remove shapes on behalf of its parent.
        child = RWBPushDrawingState(state, NO);
        assert(!state[@"rwb_shouldHideBackground"] && !state[@"rwb_didSkipFirstN"]);
        NSDictionary *grandchild = RWBPushDrawingState(state, YES);
        state[@"rwb_didSkipFirstN"] = @4;
        RWBPopDrawingState(state, grandchild);
        assert(!state[@"rwb_shouldHideBackground"] && !state[@"rwb_didSkipFirstN"]);
        RWBPopDrawingState(state, child);
        assert([state isEqualToDictionary:parent]);

        // Exceptional exits use the same finally restoration as RBLayer.
        BOOL caught = NO;
        @try {
            child = RWBPushDrawingState(state, YES);
            @try {
                state[@"rwb_didSkipFirstN"] = @1;
                [NSException raise:@"TestDrawingException" format:@"intentional"];
            } @finally {
                RWBPopDrawingState(state, child);
            }
        } @catch (NSException *exception) {
            caught = [exception.name isEqualToString:@"TestDrawingException"];
        }
        assert(caught && [state isEqualToDictionary:parent]);
        RWBPopDrawingState(state, outer);
        assert([state isEqualToDictionary:original]);

        // Consecutive displays start clean and leave unrelated state intact.
        for (int i = 0; i < 100; i++) {
            NSDictionary *saved = RWBPushDrawingState(state, YES);
            assert(!state[@"rwb_didSkipFirstN"]);
            state[@"rwb_didSkipFirstN"] = @(i);
            RWBPopDrawingState(state, saved);
            assert([state isEqualToDictionary:original]);
        }
        puts("Drawing state tests passed: nested targets, non-targets, exceptions, consecutive frames.");
    }
    return 0;
}
