//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTest.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import "TestAppContext.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SSKBaseTest

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

    [SSKEnvironment.shared.primaryStorage closeStorageForTests];

    ClearCurrentAppContextForTests();
    [SSKEnvironment clearSharedForTests];

    [super tearDown];
}

@end

NS_ASSUME_NONNULL_END
