//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import "Environment.h"
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalBaseTest

- (void)setUp
{
    NSLog(@"[%@] setUp", self.class);

    [super setUp];

    ClearCurrentAppContextForTests();
    [Environment clearSharedForTests];
    [SSKEnvironment clearSharedForTests];

    SetCurrentAppContext([TestAppContext new]);

    [MockEnvironment activate];
    [MockSSKEnvironment activate];
}

- (void)tearDown
{
    ClearCurrentAppContextForTests();
    [Environment clearSharedForTests];
    [SSKEnvironment clearSharedForTests];

    [super tearDown];
}

@end

NS_ASSUME_NONNULL_END
