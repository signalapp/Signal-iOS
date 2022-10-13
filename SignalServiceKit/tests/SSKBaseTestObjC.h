//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/MockSSKEnvironment.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;

#ifdef TESTABLE_BUILD

@interface SSKBaseTestObjC : XCTestCase

- (void)readWithBlock:(void (^)(SDSAnyReadTransaction *transaction))block;
- (void)writeWithBlock:(void (^)(SDSAnyWriteTransaction *transaction))block;

@end

#endif

NS_ASSUME_NONNULL_END
