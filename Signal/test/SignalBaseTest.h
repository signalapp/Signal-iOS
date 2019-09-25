//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MockEnvironment.h"
#import <SignalServiceKit/MockSSKEnvironment.h>
#import <XCTest/XCTest.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;

@interface SignalBaseTest : XCTestCase

@property (nonatomic, readonly, nullable) OWSPrimaryStorage *primaryStorage;

- (void)readWithBlock:(void (^)(SDSAnyReadTransaction *transaction))block;
- (void)writeWithBlock:(void (^)(SDSAnyWriteTransaction *transaction))block;

- (void)yapReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block;
- (void)yapWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block;

@end

NS_ASSUME_NONNULL_END
