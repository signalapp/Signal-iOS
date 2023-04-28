//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKBaseTestObjC.h"
#import "SDSDatabaseStorage+Objc.h"
#import "TestAppContext.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>
#import <SignalCoreKit/OWSAsserts.h>
#import <SignalCoreKit/OWSLogs.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation SSKBaseTestObjC

- (void)setUp
{
    [super setUp];

    [DDLog addLogger:DDTTYLogger.sharedInstance];

    SetCurrentAppContext([TestAppContext new], true);

    [MockSSKEnvironment activate];
    
    [GroupManager forceV1Groups];
}

- (void)tearDown
{
    [MockSSKEnvironment flushAndWait];
    [super tearDown];
}

-(void)readWithBlock:(void (^)(SDSAnyReadTransaction *))block
{
    [SDSDatabaseStorage.shared readWithBlock:block];
}

-(void)writeWithBlock:(void (^)(SDSAnyWriteTransaction *))block
{
    DatabaseStorageWrite(SDSDatabaseStorage.shared, block);
}

@end

#endif

NS_ASSUME_NONNULL_END
