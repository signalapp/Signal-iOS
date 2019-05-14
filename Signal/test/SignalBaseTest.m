//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import "Environment.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalBaseTest

- (void)setUp
{
    OWSLogInfo(@"");

    [super setUp];

    ClearCurrentAppContextForTests();
    [Environment clearSharedForTests];
    [SSKEnvironment clearSharedForTests];

    SetCurrentAppContext([TestAppContext new]);
    [SDSDatabaseStorage.shared clearGRDBStorageForTests];
    [MockSSKEnvironment activate];
    [MockEnvironment activate];
}

- (void)tearDown
{
    OWSLogInfo(@"");

    [super tearDown];
}

- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    OWSAssert(block);

    [[SSKEnvironment.shared.primaryStorage newDatabaseConnection] readWithBlock:block];
}


- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    OWSAssert(block);

    [[SSKEnvironment.shared.primaryStorage newDatabaseConnection] readWriteWithBlock:block];
}

@end

NS_ASSUME_NONNULL_END
