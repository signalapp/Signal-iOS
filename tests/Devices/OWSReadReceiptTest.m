//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceipt.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptTest : XCTestCase

@end

@implementation OWSReadReceiptTest

- (void)testDontStoreEphemeralProperties
{
    OWSReadReceipt *readReceipt = [[OWSReadReceipt alloc] initWithSenderId:@"fake-sender-id" timestamp:1];

    // Unfortunately this test will break every time you add, remove, or rename a property, but on the
    // plus side it has a chance of catching when you indadvertently remove our ephemeral properties
    // from our Mantle storage blacklist.
    NSSet<NSString *> *expected = [NSSet setWithArray:@[ @"senderId", @"uniqueId", @"timestamp" ]];
    NSSet<NSString *> *actual = [NSSet setWithArray:[readReceipt.dictionaryValue allKeys]];

    XCTAssertEqualObjects(expected, actual);
}

@end

NS_ASSUME_NONNULL_END
