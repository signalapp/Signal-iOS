//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import "Environment.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TestAppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalBaseTest

- (void)setUp
{
    NSLog(@"%@ setUp", self.logTag);

    [super setUp];

    ClearCurrentAppContextForTests();

    SetCurrentAppContext([TestAppContext new]);
}

- (void)tearDown
{
    NSLog(@"%@ tearDown", self.logTag);

    ClearCurrentAppContextForTests();

    [super tearDown];
}

@end

NS_ASSUME_NONNULL_END
