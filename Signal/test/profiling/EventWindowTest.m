#import <XCTest/XCTest.h>
#import "EventWindow.h"
#import "TestUtil.h"

@interface EventWindowTest : XCTestCase

@end

@implementation EventWindowTest
-(void) testEventWindow {
    EventWindow* w = [EventWindow eventWindowWithWindowDuration:5];
    test([w countAfterRemovingEventsBeforeWindowEndingAt:0] == 0);
    [w addEventAtTime:4];
    [w addEventAtTime:6];
    [w addEventAtTime:8];
    
    test([w countAfterRemovingEventsBeforeWindowEndingAt:8] == 3);
    test([w countAfterRemovingEventsBeforeWindowEndingAt:10] == 2);
    test([w countAfterRemovingEventsBeforeWindowEndingAt:12] == 1);
    test([w countAfterRemovingEventsBeforeWindowEndingAt:14] == 0);
    
    // going backwards not allowed
    testThrows([w countAfterRemovingEventsBeforeWindowEndingAt:8]);
}
@end
