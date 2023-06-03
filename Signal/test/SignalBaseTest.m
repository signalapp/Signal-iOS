//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SignalBaseTest.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SDSDatabaseStorage+Objc.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalBaseTest

- (void)setUp
{
    [super setUp];

    SetCurrentAppContext([TestAppContext new], YES);
    [MockSSKEnvironment activate];
    [MockSMEnvironment activate];

    [SSKEnvironment.shared setGroupsV2ForUnitTests:[GroupsV2Impl new]];
}

- (void)tearDown
{
    [MockSSKEnvironment flushAndWait];
    [super tearDown];
}

- (void)readWithBlock:(void (^NS_NOESCAPE)(SDSAnyReadTransaction *))block
{
    [SDSDatabaseStorage.shared readWithBlock:block];
}

- (void)writeWithBlock:(void (^NS_NOESCAPE)(SDSAnyWriteTransaction *))block
{
    DatabaseStorageWrite(SDSDatabaseStorage.shared, block);
}

@end

NS_ASSUME_NONNULL_END
