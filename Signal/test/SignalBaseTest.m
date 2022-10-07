//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SDSDatabaseStorage+Objc.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalBaseTest

- (void)setUp
{
    OWSLogInfo(@"");

    [super setUp];

    SetCurrentAppContext([TestAppContext new], YES);
    [MockSSKEnvironment activate];
    [MockEnvironment activate];

    ((MockSSKEnvironment *)SSKEnvironment.shared).groupsV2Ref = [GroupsV2Impl new];
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
    DatabaseStorageWrite(SDSDatabaseStorage.shared, block);
}

@end

NS_ASSUME_NONNULL_END
