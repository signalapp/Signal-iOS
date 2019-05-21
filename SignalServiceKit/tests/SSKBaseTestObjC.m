//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import "TestAppContext.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation SSKBaseTestObjC

- (void)setUp
{
    OWSLogInfo(@"%@ setUp", self.logTag);

    [super setUp];

    [DDLog addLogger:DDTTYLogger.sharedInstance];

    ClearCurrentAppContextForTests();
    SetCurrentAppContext([TestAppContext new]);

    [MockSSKEnvironment activate];
}

- (void)tearDown
{
    OWSLogInfo(@"%@ tearDown", self.logTag);

    [super tearDown];
}

-(void)readWithBlock:(void (^)(SDSAnyReadTransaction *))block
{
    [SDSDatabaseStorage.shared readWithBlock:block];
}

-(void)writeWithBlock:(void (^)(SDSAnyWriteTransaction *))block
{
    [SDSDatabaseStorage.shared writeWithBlock:block];
}

- (void)yapReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    OWSAssert(block);

    [[SSKEnvironment.shared.primaryStorage newDatabaseConnection] readWithBlock:block];
}

- (void)yapWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    OWSAssert(block);

    [[SSKEnvironment.shared.primaryStorage newDatabaseConnection] readWriteWithBlock:block];
}

@end

#endif

NS_ASSUME_NONNULL_END
