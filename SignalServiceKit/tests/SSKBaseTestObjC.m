//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "SDSDatabaseStorage+Objc.h"
#import "SSKEnvironment.h"
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
    OWSLogInfo(@"setUp");

    [super setUp];

    [DDLog addLogger:DDTTYLogger.sharedInstance];

    ClearCurrentAppContextForTests();
    SetCurrentAppContext([TestAppContext new]);

    [MockSSKEnvironment activate];
    
    [GroupManager forceV1Groups];
}

- (void)tearDown
{
    OWSLogInfo(@"tearDown");
    OWSAssertIsOnMainThread();

    // Spin the main run loop to flush any remaining async work.
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    while (!done) {
        (void)CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, true);
    }

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
