//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverterTest.h"
#import "OWSDatabaseConverter.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/OWSStorage.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (OWSDatabaseConverterTest)

+ (YapDatabaseDeserializer)logOnFailureDeserializer;

@end

#pragma mark -

@interface OWSDatabaseConverter (OWSDatabaseConverterTest)

+ (BOOL)doesDatabaseNeedToBeConverted:(NSString *)databaseFilePath;

@end

#pragma mark -

@implementation OWSDatabaseConverterTest

- (NSData *)randomDatabasePassword
{
    return [Randomness generateRandomBytes:30];
}

- (nullable NSString *)createUnconvertedDatabase:(NSData *)passwordData
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [NSUUID UUID].UUIDString;
    NSString *databaseFilePath = [temporaryDirectory stringByAppendingPathComponent:filename];

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        return passwordData;
    };
    options.enableMultiProcessSupport = YES;

    OWSAssert(options.cipherDefaultkdfIterNumber == 0);
    OWSAssert(options.kdfIterNumber == 0);
    OWSAssert(options.cipherPageSize == 0);
    OWSAssert(options.pragmaPageSize == 0);
    OWSAssert(options.pragmaJournalSizeLimit == 0);

    YapDatabase *database = [[YapDatabase alloc] initWithPath:databaseFilePath
                                                   serializer:nil
                                                 deserializer:[OWSStorage logOnFailureDeserializer]
                                                      options:options];
    OWSAssert(database);
    return database ? databaseFilePath : nil;
}

- (void)testDoesDatabaseNeedToBeConverted_Unconverted
{
    NSData *passwordData = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:passwordData];
    XCTAssertTrue([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
}

- (void)testDoesDatabaseNeedToBeConverted_Converted
{
    // TODO: When we can create converted databases.
}

- (void)testDatabaseConversion
{
    NSData *passwordData = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:passwordData];
    XCTAssertTrue([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
    [OWSDatabaseConverter convertDatabaseIfNecessary];
    XCTAssertFalse([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
}

@end

NS_ASSUME_NONNULL_END
