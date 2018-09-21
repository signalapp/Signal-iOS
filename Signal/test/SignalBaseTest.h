//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import <SignalServiceKit/MockSSKEnvironment.h>
#import <XCTest/XCTest.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalBaseTest : XCTestCase

- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block;

- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block;

@end

NS_ASSUME_NONNULL_END
