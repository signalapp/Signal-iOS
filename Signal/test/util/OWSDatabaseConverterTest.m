//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverterTest.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSStorage.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <YapDatabase/YapDatabasePrivate.h>

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabase (OWSDatabaseConverterTest)

- (void)flushInternalQueue;
- (void)flushCheckpointQueue;

@end

@interface OWSStorage (OWSDatabaseConverterTest)

+ (YapDatabaseDeserializer)logOnFailureDeserializer;
+ (void)storeKeyChainValue:(NSData *)data keychainKey:(NSString *)keychainKey;
+ (nullable NSData *)tryToLoadKeyChainValue:(NSString *)keychainKey errorHandle:(NSError **)errorHandle;

@end

#pragma mark -

@interface YapDatabaseCryptoUtils (OWSDatabaseConverterTest)

+ (NSData *)readFirstNBytesOfDatabaseFile:(NSString *)filePath byteCount:(NSUInteger)byteCount;

@end

#pragma mark -

@implementation OWSDatabaseConverterTest

- (NSData *)randomDatabasePassword
{
    return [Randomness generateRandomBytes:30];
}

- (NSData *)randomDatabaseSalt
{
    return [Randomness generateRandomBytes:(int)kSQLCipherSaltLength];
}

- (NSData *)randomDatabaseKeySpec
{
    return [Randomness generateRandomBytes:(int)kSQLCipherKeySpecLength];
}

// * Open a YapDatabase.
// * Do some work with a block.
// * Close the database.
// * Verify that the database is closed.
- (void)openYapDatabase:(NSString *)databaseFilePath
       databasePassword:(NSData *_Nullable)databasePassword
           databaseSalt:(NSData *_Nullable)databaseSalt
        databaseKeySpec:(NSData *_Nullable)databaseKeySpec
          databaseBlock:(void (^_Nonnull)(YapDatabase *))databaseBlock
{
    OWSAssertDebug(databaseFilePath.length > 0);
    OWSAssertDebug(databasePassword.length > 0 || databaseKeySpec.length > 0);
    OWSAssertDebug(databaseBlock);

    OWSLogVerbose(@"openYapDatabase: %@", databaseFilePath);
    [DDLog flushLog];

    __weak YapDatabase *_Nullable weakDatabase = nil;
    dispatch_queue_t snapshotQueue;
    dispatch_queue_t writeQueue;

    @autoreleasepool {
        YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
        options.corruptAction = YapDatabaseCorruptAction_Fail;
        if (databasePassword) {
            OWSLogInfo(@"Using password.");
            options.cipherKeyBlock = ^{
                return databasePassword;
            };
        }
        options.enableMultiProcessSupport = YES;

        if (databaseSalt) {
            OWSLogInfo(@"Using salt & unencrypted header.");
            options.cipherSaltBlock = ^{
                return databaseSalt;
            };
            options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;
        } else if (databaseKeySpec) {
            OWSLogInfo(@"Using key spec & unencrypted header.");
            options.cipherKeySpecBlock = ^{
                return databaseKeySpec;
            };
            options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;
        }

        OWSAssertDebug(options.cipherDefaultkdfIterNumber == 0);
        OWSAssertDebug(options.kdfIterNumber == 0);
        OWSAssertDebug(options.cipherPageSize == 0);
        OWSAssertDebug(options.pragmaPageSize == 0);
        OWSAssertDebug(options.pragmaJournalSizeLimit == 0);

        YapDatabase *database = [[YapDatabase alloc] initWithPath:databaseFilePath
                                                       serializer:nil
                                                     deserializer:[OWSStorage logOnFailureDeserializer]
                                                          options:options];
        OWSAssertDebug(database);

        weakDatabase = database;
        snapshotQueue = database->snapshotQueue;
        writeQueue = database->writeQueue;

        databaseBlock(database);

        [database flushInternalQueue];
        [database flushCheckpointQueue];

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

        // YapDatabase can retain cached references to the registration
        // connections for up to 5 seconds.  This can block deallocation
        // of the YapDatabase instance.  Since we're trying to block on
        // closing of the database (so that we can examine its contents
        // on disk), we wait for the worst case duration.
        [self waitForExpectationsWithTimeout:5.0
                                     handler:^(NSError *error) {
                                         if (error) {
                                             NSLog(@"Timeout Error: %@", error);
                                         }
                                     }];
    }

    // Verify that the database is indeed closed.
    YapDatabase *_Nullable strongDatabase = weakDatabase;
    OWSAssertDebug(!strongDatabase);
}

- (void)createTestDatabase:(NSString *)databaseFilePath
          databasePassword:(NSData *_Nullable)databasePassword
              databaseSalt:(NSData *_Nullable)databaseSalt
           databaseKeySpec:(NSData *_Nullable)databaseKeySpec
{
    OWSAssertDebug(databaseFilePath.length > 0);
    OWSAssertDebug(databasePassword.length > 0 || databaseKeySpec.length > 0);

    OWSAssertDebug(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:databaseSalt
          databaseKeySpec:databaseKeySpec
            databaseBlock:^(YapDatabase *database) {
                [self logHeaderOfDatabaseFile:databaseFilePath
                                        label:@"mid-creation"];

                YapDatabaseConnection *dbConnection = database.newConnection;
                [dbConnection setObject:@(YES) forKey:@"test_key_name" inCollection:@"test_collection_name"];
                [dbConnection flushTransactionsWithCompletionQueue:dispatch_get_main_queue() completionBlock:nil];
            }];

    OWSAssertDebug([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    NSError *_Nullable error = nil;
    NSDictionary *fileAttributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:databaseFilePath error:&error];
    OWSAssertDebug(fileAttributes && !error);
    OWSLogVerbose(@"test database file size: %@", fileAttributes[NSFileSize]);
}

- (BOOL)verifyTestDatabase:(NSString *)databaseFilePath
          databasePassword:(NSData *_Nullable)databasePassword
              databaseSalt:(NSData *_Nullable)databaseSalt
           databaseKeySpec:(NSData *_Nullable)databaseKeySpec
{
    OWSAssertDebug(databaseFilePath.length > 0);
    OWSAssertDebug(databasePassword.length > 0 || databaseKeySpec.length > 0);

    OWSAssertDebug([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    __block BOOL isValid = NO;
    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:databaseSalt
          databaseKeySpec:databaseKeySpec
            databaseBlock:^(YapDatabase *database) {
                YapDatabaseConnection *dbConnection = database.newConnection;
                id _Nullable value = [dbConnection objectForKey:@"test_key_name" inCollection:@"test_collection_name"];
                isValid = [@(YES) isEqual:value];
            }];

    OWSAssertDebug([[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    return isValid;
}

- (nullable NSString *)createUnconvertedDatabase:(NSData *)databasePassword
{
    return [self createDatabase:databasePassword databaseSalt:nil databaseKeySpec:nil];
}

- (NSString *)createTempDatabaseFilePath
{
    NSString *databaseFilePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"sqlite"];

    OWSLogInfo(@"databaseFilePath: %@", databaseFilePath);
    [DDLog flushLog];

    return databaseFilePath;
}

// If databaseSalt and databaseKeySpec are both nil, creates a non-converted database.
// Otherwise creates a pre-converted database.
- (nullable NSString *)createDatabase:(NSData *_Nullable)databasePassword
                         databaseSalt:(NSData *_Nullable)databaseSalt
                      databaseKeySpec:(NSData *_Nullable)databaseKeySpec
{
    OWSAssertDebug(databasePassword.length > 0 || databaseKeySpec.length > 0);

    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    [self createTestDatabase:databaseFilePath
            databasePassword:databasePassword
                databaseSalt:databaseSalt
             databaseKeySpec:databaseKeySpec];

    [self logHeaderOfDatabaseFile:databaseFilePath
                            label:@"created"];

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:databasePassword
                               databaseSalt:databaseSalt
                            databaseKeySpec:databaseKeySpec];
    OWSAssertDebug(isValid);

    return databaseFilePath;
}

#pragma  mark - Tests

- (void)testDoesDatabaseNeedToBeConverted_Unconverted
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
}

- (void)testDoesDatabaseNeedToBeConverted_ConvertedWithoutKeyspec
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSData *_Nullable databaseKeySpec = nil;
    NSString *_Nullable databaseFilePath =
        [self createDatabase:databasePassword databaseSalt:databaseSalt databaseKeySpec:databaseKeySpec];
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
}

- (void)testDoesDatabaseNeedToBeConverted_ConvertedWithKeyspec
{
    NSData *_Nullable databasePassword = nil;
    NSData *_Nullable databaseSalt = nil;
    NSData *databaseKeySpec = [self randomDatabaseKeySpec];
    NSString *_Nullable databaseFilePath =
        [self createDatabase:databasePassword databaseSalt:databaseSalt databaseKeySpec:databaseKeySpec];
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
}

// Verifies that legacy users with non-converted databases can convert.
- (void)testDatabaseConversion_WithoutKeyspec
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    __block NSData *_Nullable databaseSalt = nil;
    __block NSData *_Nullable databaseKeySpec = nil;
    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(!databaseSalt);
        OWSAssertDebug(saltData);

        databaseSalt = saltData;
        databaseKeySpec = [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];
        XCTAssert(databaseKeySpec.length == kSQLCipherKeySpecLength);

        return YES;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];
    if (error) {
        OWSLogError(@"error: %@", error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
    XCTAssertNotNil(databaseSalt);
    XCTAssertEqual(databaseSalt.length, kSQLCipherSaltLength);
    XCTAssertNotNil(databaseKeySpec);
    XCTAssertEqual(databaseKeySpec.length, kSQLCipherKeySpecLength);

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:databasePassword
                               databaseSalt:databaseSalt
                            databaseKeySpec:nil];
    XCTAssertTrue(isValid);
}

// Verifies that legacy users with non-converted databases can convert.
- (void)testDatabaseConversion_WithKeyspec
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    __block NSData *_Nullable databaseSalt = nil;

    __block NSData *_Nullable databaseKeySpec = nil;
    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(!databaseSalt);
        OWSAssertDebug(saltData);
        
        databaseSalt = saltData;
        databaseKeySpec = [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];
        XCTAssert(databaseKeySpec.length == kSQLCipherKeySpecLength);

        return YES;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];
    if (error) {
        OWSLogError(@"error: %@", error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
    XCTAssertNotNil(databaseSalt);
    XCTAssertEqual(databaseSalt.length, kSQLCipherSaltLength);
    XCTAssertNotNil(databaseKeySpec);
    XCTAssertEqual(databaseKeySpec.length, kSQLCipherKeySpecLength);

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:nil
                               databaseSalt:nil
                            databaseKeySpec:databaseKeySpec];
    XCTAssertTrue(isValid);
}

// If we fail to record the salt for some reason, we'll be unable to re-open the database
// halt the conversion in hopes that either the failure is intermittent or we can push out
// a patch to fix the problem without having lost the user's DB.
- (void)testDatabaseConversionDoesNotProceedWhenRecordingSaltFails
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    __block NSData *_Nullable databaseSalt = nil;

    __block NSData *_Nullable databaseKeySpec = nil;
    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(!databaseSalt);
        OWSAssertDebug(saltData);

        // Simulate a failure to record the new salt, e.g. if KDF returns nil
        return NO;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];

    XCTAssertNotNil(error);
    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:databasePassword
                               databaseSalt:nil
                            databaseKeySpec:databaseKeySpec];
    XCTAssertTrue(isValid);
}

// Verifies that legacy users with non-converted databases can convert.
- (void)testDatabaseConversionPerformance_WithKeyspec
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    const int kItemCount = 50 * 1000;

    // Create and populate an unconverted database.
    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:nil
          databaseKeySpec:nil
            databaseBlock:^(YapDatabase *database) {
                YapDatabaseConnection *dbConnection = database.newConnection;
                [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                    for (int i = 0; i < kItemCount; i++) {
                        NSString *key = [NSString stringWithFormat:@"key-%d", i];
                        [transaction setObject:@"test-object" forKey:key inCollection:@"test_collection_name"];
                    }
                }];
            }];

    XCTAssertTrue([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    __block NSData *_Nullable databaseSalt = nil;
    __block NSData *_Nullable databaseKeySpec = nil;
    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(!databaseSalt);
        OWSAssertDebug(saltData);

        databaseSalt = saltData;
        databaseKeySpec = [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];
        XCTAssert(databaseKeySpec.length == kSQLCipherKeySpecLength);

        return YES;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];
    if (error) {
        OWSLogError(@"error: %@", error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);
    XCTAssertNotNil(databaseSalt);
    XCTAssertEqual(databaseSalt.length, kSQLCipherSaltLength);
    XCTAssertNotNil(databaseKeySpec);
    XCTAssertEqual(databaseKeySpec.length, kSQLCipherKeySpecLength);

    // Verify the contents of the unconverted database.
    __block BOOL isValid = NO;
    [self openYapDatabase:databaseFilePath
         databasePassword:nil
             databaseSalt:nil
          databaseKeySpec:databaseKeySpec
            databaseBlock:^(YapDatabase *database) {
                YapDatabaseConnection *dbConnection = database.newConnection;
                isValid = [dbConnection numberOfKeysInCollection:@"test_collection_name"] == kItemCount;
            }];
    XCTAssertTrue(isValid);
}

// Verifies new users who create new pre-converted databases.
- (void)testDatabaseCreation_WithoutKeySpec
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSData *_Nullable databaseKeySpec = nil;
    NSString *_Nullable databaseFilePath =
        [self createDatabase:databasePassword databaseSalt:databaseSalt databaseKeySpec:databaseKeySpec];
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(saltData);

        XCTFail(@"No conversion should be necessary");
        return NO;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];
    if (error) {
        OWSLogError(@"error: %@", error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:databasePassword
                               databaseSalt:databaseSalt
                            databaseKeySpec:databaseKeySpec];
    XCTAssertTrue(isValid);
}

// Verifies new users who create new pre-converted databases.
- (void)testDatabaseCreation_WithKeySpec
{
    NSData *_Nullable databasePassword = nil;
    NSData *_Nullable databaseSalt = nil;
    NSData *databaseKeySpec = [self randomDatabaseKeySpec];
    NSString *_Nullable databaseFilePath =
        [self createDatabase:databasePassword databaseSalt:databaseSalt databaseKeySpec:databaseKeySpec];
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSAssertDebug(saltData);

        XCTFail(@"No conversion should be necessary");
        return NO;
    };

    NSError *_Nullable error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                                                 databasePassword:databasePassword
                                                                  recordSaltBlock:recordSaltBlock];
    if (error) {
        OWSLogError(@"error: %@", error);
    }
    XCTAssertNil(error);
    XCTAssertFalse([YapDatabaseCryptoUtils doesDatabaseNeedToBeConverted:databaseFilePath]);

    BOOL isValid = [self verifyTestDatabase:databaseFilePath
                           databasePassword:databasePassword
                               databaseSalt:databaseSalt
                            databaseKeySpec:databaseKeySpec];
    XCTAssertTrue(isValid);
}

// Simulates a legacy user who needs to convert their    database.
- (void)testConversionWithoutYapDatabase
{
    sqlite3 *db;
    sqlite3_stmt *stmt;
    const int ROWSTOINSERT = 3;

    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    OWSAssertDebug(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    NSData *keyData = [self randomDatabasePassword];

    /* Step 1. Create a new encrypted database. */

    int openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;

    int rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS t1 (a INTEGER PRIMARY KEY AUTOINCREMENT, b TEXT);", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "BEGIN;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_prepare_v2(db, "INSERT INTO t1(b) VALUES (?);", -1, &stmt, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    for(int row = 0; row < ROWSTOINSERT; row++) {
        rc = sqlite3_bind_text(stmt, 1, [[NSString stringWithFormat:@"%d", (int) arc4random()] UTF8String], -1, SQLITE_TRANSIENT);
        XCTAssertTrue(rc == SQLITE_OK);
        rc = sqlite3_step(stmt);
        XCTAssertTrue(rc == SQLITE_DONE);
        rc = sqlite3_reset(stmt);
        XCTAssertTrue(rc == SQLITE_OK);
    }
    rc = sqlite3_finalize(stmt);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "COMMIT;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    NSString *salt = [self executeSingleStringQuery:@"PRAGMA cipher_salt;"
                                                 db:db];

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);

    [self logHeaderOfDatabaseFile:databaseFilePath
                            label:@"Unconverted header"];

    /* Step 2. Rewrite header */

    rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA journal_size_limit = 1048576;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA user_version = 2;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    int log, ckpt;
    rc = sqlite3_wal_checkpoint_v2(db, NULL, SQLITE_CHECKPOINT_FULL, &log, &ckpt);
    XCTAssertTrue(rc == SQLITE_OK);
    OWSLogInfo(@"log = %d, ckpt = %d", log, ckpt);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);

    [self logHeaderOfDatabaseFile:databaseFilePath
                            label:@"Converted header"];

    /* Step 3. Open the database and query it */

    rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    NSString *saltPragma = [NSString stringWithFormat:@"PRAGMA cipher_salt = \"x'%@'\";", salt];
    OWSLogInfo(@"salt pragma = %@", saltPragma);
    rc = sqlite3_exec(db, [saltPragma UTF8String], NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA journal_size_limit = 1048576;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    XCTAssertEqual(2, [self executeSingleIntQuery:@"SELECT count(*) FROM sqlite_master;" db:db]);

    XCTAssertEqual(ROWSTOINSERT, [self executeSingleIntQuery:@"SELECT count(*) FROM t1;" db:db]);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);
}

- (int)executeSingleIntQuery:(NSString *)sql
                          db:(sqlite3 *)db
{
    sqlite3_stmt *stmt;

    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_step(stmt);
    XCTAssertTrue(rc = SQLITE_ROW);

    int result = sqlite3_column_int(stmt, 0);

    rc = sqlite3_finalize(stmt);
    XCTAssertTrue(rc == SQLITE_OK);

    return result;
}

- (NSString *)executeSingleStringQuery:(NSString *)sql
                                    db:(sqlite3 *)db
{
    sqlite3_stmt *stmt;

    int rc = sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_step(stmt);
    XCTAssertTrue(rc = SQLITE_ROW);
    NSString *result = [NSString stringWithFormat:@"%s", sqlite3_column_text(stmt, 0)];

    rc = sqlite3_finalize(stmt);
    XCTAssertTrue(rc == SQLITE_OK);

    return result;
}

// Simulates a new user who makes a new, pre-converted database.
- (void)testNewUserWithoutYapDatabase
{
    sqlite3 *db;
    sqlite3_stmt *stmt;
    const int ROWSTOINSERT = 3;

    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    OWSAssertDebug(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    NSData *keyData = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSString *salt = databaseSalt.hexadecimalString;

    /* Step 1. Create a new encrypted database. */

    int openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;

    int rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    NSString *saltPragma = [NSString stringWithFormat:@"PRAGMA cipher_salt = \"x'%@'\";", salt];
    OWSLogInfo(@"salt pragma = %@", saltPragma);
    rc = sqlite3_exec(db, [saltPragma UTF8String], NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS t1 (a INTEGER PRIMARY KEY AUTOINCREMENT, b TEXT);", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "BEGIN;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_prepare_v2(db, "INSERT INTO t1(b) VALUES (?);", -1, &stmt, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    for(int row = 0; row < ROWSTOINSERT; row++) {
        rc = sqlite3_bind_text(stmt, 1, [[NSString stringWithFormat:@"%d", (int) arc4random()] UTF8String], -1, SQLITE_TRANSIENT);
        XCTAssertTrue(rc == SQLITE_OK);
        rc = sqlite3_step(stmt);
        XCTAssertTrue(rc == SQLITE_DONE);
        rc = sqlite3_reset(stmt);
        XCTAssertTrue(rc == SQLITE_OK);
    }
    rc = sqlite3_finalize(stmt);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "COMMIT;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);

    /* Step 2. Open the database and query it */

    rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    //    NSString *saltPragma = [NSString stringWithFormat:@"PRAGMA cipher_salt = \"x'%@'\";", salt];
    //    OWSLogInfo(@"salt pragma = %@", saltPragma);
    rc = sqlite3_exec(db, [saltPragma UTF8String], NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA journal_size_limit = 1048576;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    XCTAssertEqual(2, [self executeSingleIntQuery:@"SELECT count(*) FROM sqlite_master;" db:db]);

    XCTAssertEqual(ROWSTOINSERT, [self executeSingleIntQuery:@"SELECT count(*) FROM t1;" db:db]);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);
}

// Similar to testNewUserWithoutYapDatabase, but does more of the
// database configuration that YapDatabase does.
- (void)testNewUserLikeYapDatabase
{
    sqlite3 *db;
    sqlite3_stmt *stmt;
    const int ROWSTOINSERT = 3;

    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    OWSAssertDebug(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    NSData *keyData = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSString *salt = databaseSalt.hexadecimalString;

    /* Step 1. Create a new encrypted database. */

    int openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;

    int rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    NSString *saltPragma = [NSString stringWithFormat:@"PRAGMA cipher_salt = \"x'%@'\";", salt];
    OWSLogInfo(@"salt pragma = %@", saltPragma);
    rc = sqlite3_exec(db, [saltPragma UTF8String], NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    {
        int status = sqlite3_exec(db, "PRAGMA auto_vacuum = FULL; VACUUM;", NULL, NULL, NULL);
        XCTAssertEqual(status, SQLITE_OK);

        // Set synchronous to normal for THIS sqlite instance.
        //
        // This does NOT affect normal connections.
        // That is, this does NOT affect YapDatabaseConnection instances.
        // The sqlite connections of normal YapDatabaseConnection instances will follow the set pragmaSynchronous value.
        //
        // The reason we hardcode normal for this sqlite instance is because
        // it's only used to write the initial snapshot value.
        // And this doesn't need to be durable, as it is initialized to zero everytime.
        //
        // (This sqlite db is also used to perform checkpoints.
        //  But a normal value won't affect these operations,
        //  as they will perform sync operations whether the connection is normal or full.)

        status = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
        XCTAssertEqual(status, SQLITE_OK);

        // Set journal_size_imit.
        //
        // We only need to do set this pragma for THIS connection,
        // because it is the only connection that performs checkpoints.

        NSString *pragma_journal_size_limit =
        [NSString stringWithFormat:@"PRAGMA journal_size_limit = %d;", 0];

        status = sqlite3_exec(db, [pragma_journal_size_limit UTF8String], NULL, NULL, NULL);
        XCTAssertEqual(status, SQLITE_OK);

        // Disable autocheckpointing.
        //
        // YapDatabase has its own optimized checkpointing algorithm built-in.
        // It knows the state of every active connection for the database,
        // so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.

        status = sqlite3_wal_autocheckpoint(db, 0);
        XCTAssertEqual(status, SQLITE_OK);
    }

    rc = sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS t1 (a INTEGER PRIMARY KEY AUTOINCREMENT, b TEXT);", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "BEGIN;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_prepare_v2(db, "INSERT INTO t1(b) VALUES (?);", -1, &stmt, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    for(int row = 0; row < ROWSTOINSERT; row++) {
        rc = sqlite3_bind_text(stmt, 1, [[NSString stringWithFormat:@"%d", (int) arc4random()] UTF8String], -1, SQLITE_TRANSIENT);
        XCTAssertTrue(rc == SQLITE_OK);
        rc = sqlite3_step(stmt);
        XCTAssertTrue(rc == SQLITE_DONE);
        rc = sqlite3_reset(stmt);
        XCTAssertTrue(rc == SQLITE_OK);
    }
    rc = sqlite3_finalize(stmt);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "COMMIT;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);

    /* Step 2. Open the database and query it */

    rc = sqlite3_open_v2([databaseFilePath UTF8String], &db, openFlags, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, [saltPragma UTF8String], NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);
    rc = sqlite3_exec(db, "PRAGMA journal_size_limit = 1048576;", NULL, NULL, NULL);
    XCTAssertTrue(rc == SQLITE_OK);

    XCTAssertEqual(2, [self executeSingleIntQuery:@"SELECT count(*) FROM sqlite_master;" db:db]);

    XCTAssertEqual(ROWSTOINSERT, [self executeSingleIntQuery:@"SELECT count(*) FROM t1;" db:db]);

    rc = sqlite3_close(db);
    XCTAssertTrue(rc == SQLITE_OK);
}

- (void)logHeaderOfDatabaseFile:(NSString *)databaseFilePath
                          label:(NSString *)label
{
    OWSAssertDebug(databaseFilePath.length > 0);
    OWSAssertDebug(label.length > 0);

    NSData *headerData =
        [YapDatabaseCryptoUtils readFirstNBytesOfDatabaseFile:databaseFilePath byteCount:kSqliteHeaderLength];
    OWSAssertDebug(headerData);
    NSMutableString *output = [NSMutableString new];
    [output appendFormat:@"Hex: %@, ", headerData.hexadecimalString];
    [output appendString:@"Ascii: "];
    NSMutableCharacterSet *characterSet = [NSMutableCharacterSet new];
    [characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
    [characterSet formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
    [characterSet formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
    [characterSet formUnionWithCharacterSet:[NSCharacterSet symbolCharacterSet]];

    const unsigned char *bytes = (const unsigned char *) headerData.bytes;
    for (NSUInteger i=0; i < headerData.length; i++) {
        unsigned char byte = bytes[i];
        if ([characterSet characterIsMember:(unichar)byte]) {
            [output appendFormat:@"%C", (unichar)byte];
        } else {
            [output appendString:@"_"];
        }
    }
    OWSLogInfo(@"%@: %@", label, output);
}


#pragma mark - keychain strategy benchmarks


- (void)verifyTestDatabase:(NSString *)databaseFilePath
      databaseKeySpecBlock:(NSData *_Nullable (^_Nullable)(void))databaseKeySpecBlock
     databasePasswordBlock:(NSData *_Nullable (^_Nullable)(void))databasePasswordBlock
         databaseSaltBlock:(NSData *_Nullable (^_Nullable)(void))databaseSaltBlock
{
    NSData *_Nullable databaseKeySpec = databaseKeySpecBlock ? databaseKeySpecBlock() : nil;
    NSData *_Nullable databasePassword = databasePasswordBlock ? databasePasswordBlock() : nil;
    NSData *_Nullable databaseSalt = databaseSaltBlock ? databaseSaltBlock() : nil;

    [self verifyTestDatabase:databaseFilePath
            databasePassword:databasePassword
                databaseSalt:databaseSalt
             databaseKeySpec:databaseKeySpec];
}

- (void)createTestDatabase:(NSString *)databaseFilePath
      databaseKeySpecBlock:(NSData *_Nullable (^_Nullable)(void))databaseKeySpecBlock
     databasePasswordBlock:(NSData *_Nullable (^_Nullable)(void))databasePasswordBlock
         databaseSaltBlock:(NSData *_Nullable (^_Nullable)(void))databaseSaltBlock
{
    NSData *_Nullable databaseKeySpec = databaseKeySpecBlock ? databaseKeySpecBlock() : nil;
    NSData *_Nullable databasePassword = databasePasswordBlock ? databasePasswordBlock() : nil;
    NSData *_Nullable databaseSalt = databaseSaltBlock ? databaseSaltBlock() : nil;

    [self createTestDatabase:databaseFilePath
            databasePassword:databasePassword
                databaseSalt:databaseSalt
             databaseKeySpec:databaseKeySpec];
}

- (void)storeTestPasswordInKeychain:(NSData *)password
{
    // legacy password length
    OWSAssertDebug(password.length == 30);
    [OWSStorage storeKeyChainValue:password keychainKey:@"_OWSTestingPassword"];
}

- (nullable NSData *)fetchTestPasswordFromKeychain
{
    NSError *error;
    NSData *password = [OWSStorage tryToLoadKeyChainValue:@"_OWSTestingPassword" errorHandle:&error];
    OWSAssertDebug(password);
    OWSAssertDebug(!error);
    // legacy password length
    OWSAssertDebug(password.length == 30);

    return password;
}

- (void)storeTestSaltInKeychain:(NSData *)salt
{
    OWSAssertDebug(salt.length == kSQLCipherSaltLength);
    [OWSStorage storeKeyChainValue:salt keychainKey:@"_OWSTestingSalt"];
}

- (nullable NSData *)fetchTestSaltFromKeychain
{
    NSError *error;
    NSData *salt = [OWSStorage tryToLoadKeyChainValue:@"_OWSTestingSalt" errorHandle:&error];
    OWSAssertDebug(salt);
    OWSAssertDebug(!error);
    OWSAssertDebug(salt.length == kSQLCipherSaltLength);
    return salt;
}

- (void)storeTestKeySpecInKeychain:(NSData *)keySpec
{
    OWSAssertDebug(keySpec.length == kSQLCipherKeySpecLength);
    [OWSStorage storeKeyChainValue:keySpec keychainKey:@"_OWSTestingKeySpec"];
}

- (nullable NSData *)fetchTestKeySpecFromKeychain
{
    NSError *error;
    NSData *keySpec = [OWSStorage tryToLoadKeyChainValue:@"_OWSTestingKeySpec" errorHandle:&error];
    OWSAssertDebug(keySpec);
    OWSAssertDebug(!error);
    OWSAssertDebug(keySpec.length == kSQLCipherKeySpecLength);

    return keySpec;
}

- (void)testWidePassphraseFetchingStrategy
{
    NSData *password = [self randomDatabasePassword];
    NSData *salt = [self randomDatabaseSalt];

    [self measureBlock:^{
        NSString *databaseFilePath = [self createTempDatabaseFilePath];

        [self createTestDatabase:databaseFilePath
            databaseKeySpecBlock:nil
            databasePasswordBlock:^() {
                return password;
            }
            databaseSaltBlock:^() {
                return salt;
            }];

        [self verifyTestDatabase:databaseFilePath
            databaseKeySpecBlock:nil
            databasePasswordBlock:^() {
                return password;
            }
            databaseSaltBlock:^() {
                return salt;
            }];
    }];
}

- (void)testGranularPassphraseFetchingStrategy
{
    NSData *password = [self randomDatabasePassword];
    NSData *salt = [self randomDatabaseSalt];
    [self storeTestPasswordInKeychain:password];
    [self storeTestSaltInKeychain:salt];

    [self measureBlock:^{

        NSString *databaseFilePath = [self createTempDatabaseFilePath];


        [self createTestDatabase:databaseFilePath
            databaseKeySpecBlock:nil
            databasePasswordBlock:^() {
                return [self fetchTestPasswordFromKeychain];
            }
            databaseSaltBlock:^() {
                return [self fetchTestSaltFromKeychain];
            }];

        [self verifyTestDatabase:databaseFilePath
            databaseKeySpecBlock:nil
            databasePasswordBlock:^() {
                return [self fetchTestPasswordFromKeychain];
            }
            databaseSaltBlock:^() {
                return [self fetchTestSaltFromKeychain];
            }];
    }];
}

- (void)testGranularKeySpecFetchingStrategy
{
    NSData *keySpec = [self randomDatabaseKeySpec];
    [self storeTestKeySpecInKeychain:keySpec];

    [self measureBlock:^{
        NSString *databaseFilePath = [self createTempDatabaseFilePath];

        [self createTestDatabase:databaseFilePath
             databaseKeySpecBlock:^() {
                 return [self fetchTestKeySpecFromKeychain];
             }
            databasePasswordBlock:nil
                databaseSaltBlock:nil];

        [self verifyTestDatabase:databaseFilePath
             databaseKeySpecBlock:^() {
                 return [self fetchTestKeySpecFromKeychain];
             }
            databasePasswordBlock:nil
                databaseSaltBlock:nil];
    }];
}

- (void)testWideKeyFetchingStrategy
{
    NSData *keySpec = [self randomDatabaseKeySpec];

    [self measureBlock:^{
        NSString *databaseFilePath = [self createTempDatabaseFilePath];

        [self createTestDatabase:databaseFilePath
             databaseKeySpecBlock:^() {
                 return keySpec;
             }
            databasePasswordBlock:nil
                databaseSaltBlock:nil];

        [self verifyTestDatabase:databaseFilePath
             databaseKeySpecBlock:^() {
                 return keySpec;
             }
            databasePasswordBlock:nil
                databaseSaltBlock:nil];
    }];
}

@end

NS_ASSUME_NONNULL_END
