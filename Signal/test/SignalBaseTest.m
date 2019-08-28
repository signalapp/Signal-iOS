//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import "Environment.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TestAppContext.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalBaseTest ()

@property (nonatomic) YapDatabaseConnection *ydbConnection;

@end

#pragma mark -

@implementation SignalBaseTest

#pragma mark - Dependencies

- (nullable OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (void)setUp
{
    OWSLogInfo(@"");

    [super setUp];

    ClearCurrentAppContextForTests();
    [Environment clearSharedForTests];
    [SSKEnvironment clearSharedForTests];

    SetCurrentAppContext([TestAppContext new]);
    [MockSSKEnvironment activate];
    [MockEnvironment activate];

    self.ydbConnection = [SSKEnvironment.shared.primaryStorage newDatabaseConnection];
}

- (void)tearDown
{
    OWSLogInfo(@"");

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
    OWSAssert(self.ydbConnection);

    [self.ydbConnection readWithBlock:block];
}

- (void)yapWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    OWSAssert(block);
    OWSAssert(self.ydbConnection);

    [self.ydbConnection readWriteWithBlock:block];
}

@end

NS_ASSUME_NONNULL_END
