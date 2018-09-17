//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTest.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import "TestAppContext.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation SSKBaseTest

- (void)setUp
{
    NSLog(@"%@ setUp", self.logTag);

    [super setUp];

    ClearCurrentAppContextForTests();
    SetCurrentAppContext([TestAppContext new]);

    [MockSSKEnvironment activate];
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

#endif

NS_ASSUME_NONNULL_END
