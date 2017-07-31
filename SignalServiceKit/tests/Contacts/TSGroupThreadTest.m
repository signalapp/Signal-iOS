//  Created by Michael Kirk on 11/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSGroupThread.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSGroupThreadTest : XCTestCase

@end

@implementation TSGroupThreadTest

- (void)testHasSafetyNumbers
{
    TSGroupThread *groupThread = [TSGroupThread new];
    XCTAssertFalse(groupThread.hasSafetyNumbers);
}

@end

NS_ASSUME_NONNULL_END
