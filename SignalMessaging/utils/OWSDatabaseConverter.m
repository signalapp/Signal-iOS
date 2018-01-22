//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverter.h"
#import "sqlite3.h"
#import <SignalServiceKit/NSData+hexString.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kSqliteHeaderLength = 32;

@interface OWSStorage (OWSDatabaseConverter)

+ (YapDatabaseDeserializer)logOnFailureDeserializer;

@end

#pragma mark -

@implementation OWSDatabaseConverter

+ (NSData *)readFirstNBytesOfDatabaseFile:(NSString *)filePath byteCount:(NSUInteger)byteCount
{
    OWSAssert(filePath.length > 0);

    @autoreleasepool {
        NSError *error;
        // We use NSDataReadingMappedAlways instead of NSDataReadingMappedIfSafe because
        // we know the database will always exist for the duration of this instance of NSData.
        NSData *_Nullable data = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:filePath]
                                                       options:NSDataReadingMappedAlways
                                                         error:&error];
        if (!data || error) {
            DDLogError(@"%@ Couldn't read database file header.", self.logTag);
            // TODO: Make a convenience method (on a category of NSException?) that
            // flushes DDLog before raising a terminal exception.
            [NSException raise:@"Couldn't read database file header" format:@""];
        }
        // Pull this constant out so that we can use it in our YapDatabase fork.
        NSData *_Nullable headerData = [data subdataWithRange:NSMakeRange(0, byteCount)];
        if (!headerData || headerData.length != byteCount) {
            [NSException raise:@"Database file header has unexpected length"
                        format:@"Database file header has unexpected length: %zd", headerData.length];
        }
        return [headerData copy];
    }
}

+ (BOOL)doesDatabaseNeedToBeConverted:(NSString *)databaseFilePath
{
    OWSAssert(databaseFilePath.length > 0);

    if (![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]) {
        DDLogVerbose(@"%@ database file not found.", self.logTag);
        return nil;
    }

    NSData *headerData = [self readFirstNBytesOfDatabaseFile:databaseFilePath byteCount:kSqliteHeaderLength];
    OWSAssert(headerData);

    NSString *kUnencryptedHeader = @"SQLite format 3\0";
    NSData *unencryptedHeaderData = [kUnencryptedHeader dataUsingEncoding:NSUTF8StringEncoding];
    BOOL isUnencrypted = [unencryptedHeaderData
        isEqualToData:[headerData subdataWithRange:NSMakeRange(0, unencryptedHeaderData.length)]];
    if (isUnencrypted) {
        DDLogVerbose(@"%@ doesDatabaseNeedToBeConverted; legacy database header already decrypted.", self.logTag);
        return NO;
    }

    return YES;
}

+ (nullable NSError *)convertDatabaseIfNecessary
{
    NSString *databaseFilePath = [TSStorageManager legacyDatabaseFilePath];

    NSError *error;
    NSData *_Nullable databasePassword = [OWSStorage tryToLoadDatabasePassword:&error];
    if (!databasePassword || error) {
        return (error
                ?: OWSErrorWithCodeDescription(
                       OWSErrorCodeDatabaseConversionFatalError, @"Failed to load database password"));
    }

    OWSDatabaseSaltBlock saltBlock = ^(NSData *saltData) {
        [OWSStorage storeDatabaseSalt:saltData];
    };

    return [self convertDatabaseIfNecessary:databaseFilePath databasePassword:databasePassword saltBlock:saltBlock];
}

// TODO upon failure show user error UI
// TODO upon failure anything we need to do "back out" partial migration
+ (nullable NSError *)convertDatabaseIfNecessary:(NSString *)databaseFilePath
                                databasePassword:(NSData *)databasePassword
                                       saltBlock:(OWSDatabaseSaltBlock)saltBlock
{
    if (![self doesDatabaseNeedToBeConverted:databaseFilePath]) {
        return nil;
    }

    return [self convertDatabase:(NSString *)databaseFilePath databasePassword:databasePassword saltBlock:saltBlock];
}

+ (nullable NSError *)convertDatabase:(NSString *)databaseFilePath
                     databasePassword:(NSData *)databasePassword
                            saltBlock:(OWSDatabaseSaltBlock)saltBlock
{
    OWSAssert(databaseFilePath.length > 0);
    OWSAssert(databasePassword.length > 0);
    OWSAssert(saltBlock);

    DDLogVerbose(@"%@ databasePassword: %@", self.logTag, databasePassword.hexadecimalString);

    NSData *sqlCipherSaltData;
    {
        NSData *headerData = [self readFirstNBytesOfDatabaseFile:databaseFilePath byteCount:kSqliteHeaderLength];
        OWSAssert(headerData);

        const NSUInteger kSQLCipherSaltLength = 16;
        OWSAssert(headerData.length >= kSQLCipherSaltLength);
        sqlCipherSaltData = [headerData subdataWithRange:NSMakeRange(0, kSQLCipherSaltLength)];

        DDLogVerbose(@"%@ sqlCipherSaltData: %@", self.logTag, sqlCipherSaltData.hexadecimalString);

        // Make sure we successfully persist the salt (persumably in the keychain) before
        // proceeding with the database conversion or we could leave the app in an
        // unrecoverable state.
        saltBlock(sqlCipherSaltData);
    }

    //    Hello Matthew,
    //
    //    I hope you're doing well. We've just pushed some changes out to the SQLCipher prerelease branch on GitHub that
    //    implement the functionality we talked about that add a few new options:
    //
    //    1. PRAGMA cipher_plaintext_header_size - set or query the number of bytes to be left unencrypted on the start
    //    of the first page. This pragma would be called after keying the database, but before use. In our testing 32
    //    works for iOS
    //        2. PRAGMA cipher_default_plaintext_header_size - set the "global" default to be used when opening database
    //        connections
    //        3. PRAGMA cipher_salt - set or query the salt for the database
    //
    //            When working with the SQLCipherVsSharedData application, there are two changes required. First, modify
    //            the Podfile to reference SQLCipher with these changes:
    //
    //            pod 'SQLCipher', :git => 'https://github.com/sqlcipher/sqlcipher.git', :commit => 'd5c2bec'
    //
    //            Next, set the plaintext header size immediately after the key is provided:
    //
    //            int status = sqlite3_exec(db, "PRAGMA cipher_plaintext_header_size = 32;", NULL, NULL, NULL);
    //
    //
    //    This should allow the demo app to background correctly.
    //
    //    In practice, for a real application, the other changes we talked about on the phone need occur, i.e. to
    //    provide the salt to the application explicitly. The application can use a raw key spec, where the 96 hex are
    //    provide (i.e. 64 hex for the 256 bit key, followed by 32 hex for the 128 bit salt) using explicit BLOB syntax,
    //    e.g.
    //
    //        x'98483C6EB40B6C31A448C22A66DED3B5E5E8D5119CAC8327B655C8B5C483648101010101010101010101010101010101'
    //
    //        Alternately, the application can use the new cipher_salt PRAGMA to provide 32 hex to use as salt in
    //        conjunction with a standard derived key, e.g.
    //
    //        PRAGMA cipher_salt = "x'01010101010101010101010101010101'";
    //
    //    Since you mentioned the Signal application is using a derived key, the second option might be easiest. You
    //    could load the first 16 bytes of the existing file, or query the database using cipher_salt, and then store
    //    that along side the key in the keychain. Then following migration you can provide both the key and the salt
    //    explicitly.
    //
    //    With respect to migrating existing databases, it is possible to open a database, set the pragma, modify the
    //    first page, then checkpoint to ensure that all WAL frames are written back to the main database. This allows
    //    you to "decrypt" the first part of the header almost instantaneously, without having to re-encrypt all of the
    //    content. Keep in mind that you'll need to record the salt separately in this case. There are a few examples of
    //    this in the test cases we wrote up for this new functionality, starting here:
    //
    // https://github.com/sqlcipher/sqlcipher/blob/d5c2bec7688cef298292906c029d26b2c043219d/test/crypto.test#L2669
    //
    //    I was hoping you could take a look at this new functionality, provide feedback, and perform some initial
    //    testing on your side. Please let us know if you have any questions, or would like to discuss the specifics of
    //    implementation further. Thanks!
    //
    //        Cheers,
    //        Stephen

    // -----------------------------------------------------------
    //
    // This block was derived from [Yapdatabase openDatabase].
    sqlite3 *db;
    int status;
    {
        int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;
        status = sqlite3_open_v2([databaseFilePath UTF8String], &db, flags, NULL);
        if (status != SQLITE_OK) {
            // There are a few reasons why the database might not open.
            // One possibility is if the database file has become corrupt.

            // Sometimes the open function returns a db to allow us to query it for the error message.
            // The openConfigCreate block will close it for us.
            if (db) {
                DDLogError(@"Error opening database: %d %s", status, sqlite3_errmsg(db));
            } else {
                DDLogError(@"Error opening database: %d", status);
            }

            return OWSErrorWithCodeDescription(OWSErrorCodeDatabaseConversionFatalError, @"Failed to open database");
        }
    }

    // -----------------------------------------------------------
    //
    // This block was derived from [Yapdatabase configureEncryptionForDatabase].
    {
        NSData *keyData = databasePassword;

        // Setting the encrypted database page size
        status = sqlite3_key(db, [keyData bytes], (int)[keyData length]);
        if (status != SQLITE_OK) {
            DDLogError(@"Error setting SQLCipher key: %d %s", status, sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(
                OWSErrorCodeDatabaseConversionFatalError, @"Failed to set SQLCipher key");
        }
    }

    // -----------------------------------------------------------
    //
    // This block was derived from [Yapdatabase configureDatabase].
    {
        status = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            DDLogError(@"Error setting PRAGMA journal_mode: %d %s", status, sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(OWSErrorCodeDatabaseConversionFatalError, @"Failed to set WAL mode");
        }

        // TODO verify we need to do this.
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
        if (status != SQLITE_OK) {
            DDLogError(@"Error setting PRAGMA synchronous: %d %s", status, sqlite3_errmsg(db));
            // This isn't critical, so we can continue.
        }

        // Set journal_size_imit.
        //
        // We only need to do set this pragma for THIS connection,
        // because it is the only connection that performs checkpoints.

        NSInteger defaultPragmaJournalSizeLimit = 0;
        NSString *pragma_journal_size_limit =
            [NSString stringWithFormat:@"PRAGMA journal_size_limit = %ld;", (long)defaultPragmaJournalSizeLimit];

        status = sqlite3_exec(db, [pragma_journal_size_limit UTF8String], NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            DDLogError(@"Error setting PRAGMA journal_size_limit: %d %s", status, sqlite3_errmsg(db));
            // This isn't critical, so we can continue.
        }

        // Disable autocheckpointing.
        //
        // YapDatabase has its own optimized checkpointing algorithm built-in.
        // It knows the state of every active connection for the database,
        // so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.
        sqlite3_wal_autocheckpoint(db, 0);

        // END DB setup copied from YapDatabase
        // BEGIN SQLCipher migration
    }

#ifdef DEBUG
    // We can obtain the database salt in two ways: by reading the first 16 bytes of the encrypted
    // header OR by using "PRAGMA cipher_salt".  In DEBUG builds, we verify that these two values
    // match.
    {
        sqlite3_stmt *statement;

        char *stmt = "PRAGMA cipher_salt;";

        status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt) + 1, &statement, NULL);
        if (status != SQLITE_OK) {
            DDLogError(@"%@ Error extracting database salt: %d, error: %s", self.logTag, status, sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(
                OWSErrorCodeDatabaseConversionFatalError, @"Error extracting database salt");
        }

        status = sqlite3_step(statement);
        if (status != SQLITE_ROW) {
            DDLogError(@"%@ Missing database salt: %d, error: %s", self.logTag, status, sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(OWSErrorCodeDatabaseConversionFatalError, @"Missing database salt");
        }

        const unsigned char *valueBytes = sqlite3_column_text(statement, 0);
        int valueLength = sqlite3_column_bytes(statement, 0);
        OWSAssert(valueLength == kSqliteHeaderLength);
        OWSAssert(valueBytes != NULL);

        NSString *saltString =
            [[NSString alloc] initWithBytes:valueBytes length:valueLength encoding:NSUTF8StringEncoding];

        sqlite3_finalize(statement);
        statement = NULL;

        DDLogVerbose(@"%@ saltString: %@", self.logTag, saltString);

        OWSAssert([sqlCipherSaltData.hexadecimalString isEqualToString:saltString]);
    }
#endif

    // -----------------------------------------------------------
    //
    // SQLCipher migration
    {
        NSString *setPlainTextHeaderPragma =
            [NSString stringWithFormat:@"PRAGMA cipher_plaintext_header_size = %zd;", kSqliteHeaderLength];

        status = sqlite3_exec(db, [setPlainTextHeaderPragma UTF8String], NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            DDLogError(@"Error setting PRAGMA cipher_plaintext_header_size = %zd: status: %d, error: %s",
                kSqliteHeaderLength,
                status,
                sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(
                OWSErrorCodeDatabaseConversionFatalError, @"Failed to set PRAGMA cipher_plaintext_header_size");
        }

        // Modify the first page, so that SQLCipher will overwrite, respecting our new cipher_plaintext_header_size
        NSString *tableName = [NSString stringWithFormat:@"signal-migration-%@", [NSUUID new].UUIDString];
        NSString *modificationSQL =
            [NSString stringWithFormat:@"CREATE TABLE \"%@\"(a integer); INSERT INTO \"%@\"(a) VALUES (1);",
                      tableName,
                      tableName];
        DDLogInfo(@"%@ modificationSQL: %@", self.logTag, modificationSQL);
        status = sqlite3_exec(db, [modificationSQL UTF8String], NULL, NULL, NULL);
        if (status != SQLITE_OK) {
            DDLogError(@"%@ Error modifying first page: %d, error: %s", self.logTag, status, sqlite3_errmsg(db));
            return OWSErrorWithCodeDescription(OWSErrorCodeDatabaseConversionFatalError, @"Error modifying first page");
        }

        // Force a checkpoint so that the plaintext is written to the actual DB file, not just living in the WAL.
        // TODO do we need/want the earlier checkpoint if we're checkpointing here?
        sqlite3_wal_autocheckpoint(db, 0);

        sqlite3_close(db);
    }

    return nil;
}

@end

NS_ASSUME_NONNULL_END
