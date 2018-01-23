//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverterTest.h"
#import "OWSDatabaseConverter.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/NSData+hexString.h>
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
              databaseSalt:(NSData *_Nullable)databaseSalt
{
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(databasePassword.length > 0);

    OWSAssert(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);

    [self openYapDatabase:databaseFilePath
         databasePassword:databasePassword
             databaseSalt:databaseSalt
            databaseBlock:^(YapDatabase *database) {
                [self logHeaderOfDatabaseFile:databaseFilePath
                                        label:@"mid-creation"];

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
    return [self createDatabase:databasePassword
                   databaseSalt:nil];
}

- (NSString *)createTempDatabaseFilePath
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"];
    NSString *databaseFilePath = [temporaryDirectory stringByAppendingPathComponent:filename];
    
    DDLogInfo(@"%@ databaseFilePath: %@", self.logTag, databaseFilePath);
    [DDLog flushLog];

    return databaseFilePath;
}

// If databaseSalt is nil, creates a non-converted database.
// Otherwise creates a pre-converted database.
- (nullable NSString *)createDatabase:(NSData *)databasePassword
                         databaseSalt:(NSData *_Nullable)databaseSalt
{
    NSString *databaseFilePath = [self createTempDatabaseFilePath];

    [self createTestDatabase:databaseFilePath databasePassword:databasePassword databaseSalt:databaseSalt];

    [self logHeaderOfDatabaseFile:databaseFilePath
                            label:@"created"];

    BOOL isValid = [self verifyTestDatabase:databaseFilePath databasePassword:databasePassword databaseSalt:databaseSalt];
    OWSAssert(isValid);

    return databaseFilePath;
}

#pragma  mark - Tests

- (void)testDoesDatabaseNeedToBeConverted_Unconverted
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSString *_Nullable databaseFilePath = [self createUnconvertedDatabase:databasePassword];
    XCTAssertTrue([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
}

- (void)testDoesDatabaseNeedToBeConverted_Converted
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSString *_Nullable databaseFilePath = [self createDatabase:databasePassword
                                                   databaseSalt:databaseSalt];
    XCTAssertFalse([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
}

// Verifies that legacy users with non-converted databases can convert.
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

// Verifies new users who create new pre-converted databases.
- (void)testDatabaseCreation
{
    NSData *databasePassword = [self randomDatabasePassword];
    NSData *databaseSalt = [self randomDatabaseSalt];
    NSString *_Nullable databaseFilePath = [self createDatabase:databasePassword
                                                   databaseSalt:databaseSalt];
    XCTAssertFalse([OWSDatabaseConverter doesDatabaseNeedToBeConverted:databaseFilePath]);
    
    OWSDatabaseSaltBlock saltBlock = ^(NSData *saltData) {
        OWSAssert(saltData);
        
        XCTFail(@"%s No conversion should be necessary", __PRETTY_FUNCTION__);
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

// Simulates a legacy user who needs to convert their    database.
- (void)testConversionWithoutYapDatabase
{
    sqlite3 *db;
    sqlite3_stmt *stmt;
    const int ROWSTOINSERT = 3;
    
    NSString *databaseFilePath = [self createTempDatabaseFilePath];
    
    OWSAssert(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);
    
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
    DDLogInfo(@"log = %d, ckpt = %d", log, ckpt);
    
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
    DDLogInfo(@"salt pragma = %@", saltPragma);
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
    
    OWSAssert(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);
    
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
    DDLogInfo(@"salt pragma = %@", saltPragma);
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
    //    DDLogInfo(@"salt pragma = %@", saltPragma);
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
    
    OWSAssert(![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]);
    
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
    DDLogInfo(@"salt pragma = %@", saltPragma);
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
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(label.length > 0);

    NSData *headerData = [OWSDatabaseConverter readFirstNBytesOfDatabaseFile:databaseFilePath byteCount:kSqliteHeaderLength];
    OWSAssert(headerData);
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
    DDLogInfo(@"%@: %@", label, output);
}

@end

NS_ASSUME_NONNULL_END
