//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"

@interface PushManagerTest : SignalBaseTest

@end

@implementation PushManagerTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

/**
 *  This test verifies that the enum containing the notifications types doesn't change for iOS7 support.
 */

- (void)testNotificationTypesForiOS7 {
    XCTAssert(UIRemoteNotificationTypeAlert == UIUserNotificationTypeAlert, @"iOS 7 <-> 8 compatibility");
    XCTAssert(UIRemoteNotificationTypeSound == UIUserNotificationTypeSound, @"iOS 7 <-> 8 compatibility");
    XCTAssert(UIRemoteNotificationTypeBadge == UIUserNotificationTypeBadge, @"iOS 7 <-> 8 compatibility");
}

@end
