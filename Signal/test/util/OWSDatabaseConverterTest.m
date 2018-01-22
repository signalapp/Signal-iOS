//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverterTest.h"
#import "OWSDatabaseConverter.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/OWSStorage.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabasePrivate.h>

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

// * Open a YapDatabase.
// * Do some work with a block.
// * Close the database.
// * Verify that the database is closed.
- (void)openYapDatabase:(NSString *)databaseFilePath
       databasePassword:(NSData *)databasePassword
           databaseSalt:(NSData *_Nullable)databaseSalt
          databaseBlock:(void (^_Nonnull)(YapDatabase *))databaseBlock
{
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(databasePassword.length > 0);
    OWSAssert(databaseBlock);

    DDLogVerbose(@"openYapDatabase: %@", databaseFilePath);
    [DDLog flushLog];

    __weak YapDatabase *_Nullable weakDatabase = nil;
    dispatch_queue_t snapshotQueue;
    dispatch_queue_t writeQueue;

    @autoreleasepool {
        YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
        options.corruptAction = YapDatabaseCorruptAction_Fail;
        options.cipherKeyBlock = ^{
            return databasePassword;
        };
        options.enableMultiProcessSupport = YES;

        if (databaseSalt) {
            DDLogInfo(@"%@ Using salt & unencrypted header.", self.logTag);
            options.cipherSaltBlock = ^{
                return databaseSalt;
            };
            options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;
        }

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

        weakDatabase = database;
        snapshotQueue = database->snapshotQueue;
        writeQueue = database->writeQueue;

        databaseBlock(database);

        // Close the database.
        database = nil;
    }

    // Flush the database's queues, which may contain lingering
    // references to the database.
    dispatch_sync(snapshotQueue,
        ^{
        });
    dispatch_sync(writeQueue,
        ^{
        });

    // Wait for notifications from writes to be fired.
    {
        XCTestExpectation *expectation = [self expectationWithDescription:@"Database modified notifications"];

        dispatch_async(dispatch_get_main_queue(), ^{
            // Database modified notifications are fired on the main queue.
            // Once this block executes, the main queue has been flushed
            // and we know that all database modified notifications are
            // complete.
            [expectation fulfill];
        });

        [self waitForExpectationsWithTimeout:5.0
                                     handler:^(NSError *error) {
                                         if (error) {
                                             NSLog(@"Timeout Error: %@", error);
                                         }
                                     }];
    }

    // Verify that the database is indeed closed.
    YapDatabase *_Nullable strongDatabase = weakDatabase;
    OWSAssert(!strongDatabase);
}

- (void)createTestDatabase:(NSString *)databaseFilePath databasePassword:(NSData *)databasePassword
{
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(databasePassword.length > 0);

    OWSAssert(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:nil
            databaseBlock:^(YapDatabase *database) {
                YapDatabaseConnection *dbConnection = database.newConnection;
                [dbConnection setObject:@(YES) forKey:@"test_key_name" inCollection:@"test_collection_name"];
                [dbConnection flushTransactionsWithCompletionQueue:dispatch_get_main_queue() completionBlock:nil];
            }];

    OWSAssert([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    NSError *_Nullable error = nil;
    NSDictionary *fileAttributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:databaseFilePath error:&error];
    OWSAssert(fileAttributes && !error);
    DDLogVerbose(@"%@ test database file size: %@", self.logTag, fileAttributes[NSFileSize]);
}

- (BOOL)verifyTestDatabase:(NSString *)databaseFilePath
          databasePassword:(NSData *)databasePassword
              databaseSalt:(NSData *_Nullable)databaseSalt
{
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(databasePassword.length > 0);

    OWSAssert([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    __block BOOL isValid = NO;
    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:databaseSalt
            databaseBlock:^(YapDatabase *database) {
                YapDatabaseConnection *dbConnection = database.newConnection;
                id _Nullable value = [dbConnection objectForKey:@"test_key_name" inCollection:@"test_collection_name"];
                isValid = [@(YES) isEqual:value];
            }];

    OWSAssert([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    return isValid;
}

- (nullable NSString *)createUnconvertedDatabase:(NSData *)databasePassword
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"];
    NSString *databaseFilePath = [temporaryDirectory stringByAppendingPathComponent:filename];

    DDLogInfo(@"%@ databaseFilePath: %@", self.logTag, databaseFilePath);

    [self createTestDatabase:databaseFilePath databasePassword:databasePassword];

    BOOL isValid = [self verifyTestDatabase:databaseFilePath databasePassword:databasePassword databaseSalt:nil];
    OWSAssert(isValid);

    return databaseFilePath;
}

- (void)testDoesDatabaseNeedToBeConverted_Unconverted
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
}

- (void)testDoesDatabaseNeedToBeConverted_Converted
{
    // TODO: When we can create converted databases.
}

- (void)testDatabaseConversion
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);

    __block NSData *_Nullable databaseSalt = nil;
    OWSDatabaseSaltBlock saltBlock = ^(NSData *saltData) {
        OWSAssert(!databaseSalt);
        OWSAssert(saltData);

        databaseSalt = saltData;
    };
    NSError *_Nullable error = [OWSDatabaseConverter convertDatabaseIfNecessary:databaseFilePath
                                                               databasePassword:databasePassword
                                                                      saltBlock:saltBlock];
    if (error) {
        DDLogError(@"%s error: %@", __PRETTY_FUNCTION__, error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);

    BOOL isValid =
        [self verifyTestDatabase:databaseFilePath databasePassword:databasePassword databaseSalt:databaseSalt];
    XCTAssertTrue(isValid);
}

@end

NS_ASSUME_NONNULL_END
