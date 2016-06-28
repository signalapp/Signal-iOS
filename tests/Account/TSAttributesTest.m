//
//  TSAttributesTest.m
//  Signal
//
//  Created by Michael Kirk on 6/27/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TSAttributes.h"
#import "TSAccountManager.h"

@interface TSAttributesTest : XCTestCase

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
    NSDictionary *expected = @{ @"AuthKey": @"fake-server-auth-token",
                                @"registrationId": registrationId,
                                @"signalingKey": @"fake-signaling-key",
                                @"voice": @1 };

    NSDictionary *actual = [TSAttributes attributesWithSignalingKey:@"fake-signaling-key"
                                                    serverAuthToken:@"fake-server-auth-token"];

    XCTAssertEqualObjects(expected, actual);
}

@end
