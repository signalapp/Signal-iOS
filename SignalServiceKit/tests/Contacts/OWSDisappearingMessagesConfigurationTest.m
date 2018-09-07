//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfiguration.h"
#import "SSKBaseTest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesConfigurationTest : SSKBaseTest

@end

@implementation OWSDisappearingMessagesConfigurationTest

- (void)testDictionaryValueDidChange
{
    OWSDisappearingMessagesConfiguration *configuration =
        [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:@"fake-thread-id"
                                                               enabled:YES
                                                       durationSeconds:10];
    XCTAssertTrue(configuration.dictionaryValueDidChange);

    [configuration save];
    XCTAssertFalse(configuration.dictionaryValueDidChange);

    configuration.enabled = NO;
    XCTAssertTrue(configuration.dictionaryValueDidChange);

    configuration.enabled = YES;
    XCTAssertFalse(configuration.dictionaryValueDidChange);

    OWSDisappearingMessagesConfiguration *reloadedConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:@"fake-thread-id"];
    XCTAssertNotNil(reloadedConfiguration); // Sanity Check.
    XCTAssertFalse(reloadedConfiguration.dictionaryValueDidChange);

    reloadedConfiguration.durationSeconds = 30;
    XCTAssertTrue(reloadedConfiguration.dictionaryValueDidChange);

    reloadedConfiguration.durationSeconds = 10;
    XCTAssertFalse(reloadedConfiguration.dictionaryValueDidChange);
}

- (void)testDontStoreEphemeralProperties
{
    OWSDisappearingMessagesConfiguration *configuration =
        [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:@"fake-thread-id"
                                                               enabled:YES
                                                       durationSeconds:10];


    // Unfortunately this test will break every time you add, remove, or rename a property, but on the
    // plus side it has a chance of catching when you indadvertently remove our ephemeral properties
    // from our Mantle storage blacklist.
    NSArray<NSString *> *expected = @[ @"enabled", @"durationSeconds", @"uniqueId" ];

    XCTAssertEqualObjects(expected, [configuration.dictionaryValue allKeys]);
}

@end

NS_ASSUME_NONNULL_END
