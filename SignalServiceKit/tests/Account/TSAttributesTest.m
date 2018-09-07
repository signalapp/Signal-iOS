//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"
#import "SSKBaseTest.h"
#import "TSAccountManager.h"
#import <XCTest/XCTest.h>

@interface TSAttributesTest : SSKBaseTest

@end

@implementation TSAttributesTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testAttributesWithSignalingKey {
    
    NSString *registrationId = [NSString stringWithFormat:@"%i", [TSAccountManager getOrGenerateRegistrationId]];
    NSDictionary *expected = @{
                               @"AuthKey" : @"fake-server-auth-token",
                               @"registrationId" : registrationId,
                               @"signalingKey" : @"fake-signaling-key",
                               @"video" : @1,
                               @"voice" : @1
                               };
    
    NSDictionary *actual = [TSAttributes attributesWithSignalingKey:@"fake-signaling-key"
                                                    serverAuthToken:@"fake-server-auth-token"
                                              manualMessageFetching:NO
                                                                pin:nil];
    
    XCTAssertEqualObjects(expected, actual);
}

@end
