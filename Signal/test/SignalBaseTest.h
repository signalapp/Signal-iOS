//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;

@interface SignalBaseTest : XCTestCase

- (void)readWithBlock:(void (^NS_NOESCAPE)(SDSAnyReadTransaction *transaction))block;
- (void)writeWithBlock:(void (^NS_NOESCAPE)(SDSAnyWriteTransaction *transaction))block;

@end

NS_ASSUME_NONNULL_END
