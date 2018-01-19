//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverter.h"
#import "sqlite3.h"
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOWSDatabaseConverterErrorDomain = @"OWSOWSDatabaseConverterErrorDomain";
const int kCouldNotOpenDatabase = 1;
const int kCouldNotLoadDatabasePassword = 2;

@implementation OWSDatabaseConverter

+ (BOOL)doesDatabaseNeedToBeConverted:(NSString *)databaseFilePath
{
    OWSAssert(databaseFilePath.length > 0);

    if (![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]) {
        DDLogVerbose(@"%@ Skipping database conversion; no legacy database found.", self.logTag);
        return NO;
    }
    NSError *error;
    // We use NSDataReadingMappedAlways instead of NSDataReadingMappedIfSafe because
    // we know the database will always exist for the duration of this instance of NSData.
    NSData *_Nullable data = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:databaseFilePath]
                                                   options:NSDataReadingMappedAlways
                                                     error:&error];
    if (!data || error) {
        DDLogError(@"%@ Couldn't read legacy database file header.", self.logTag);
        // TODO: Make a convenience method (on a category of NSException?) that
        // flushes DDLog before raising a terminal exception.
        [NSException raise:@"Couldn't read legacy database file header" format:@""];
    }
    // Pull this constant out so that we can use it in our YapDatabase fork.
    const int kSqliteHeaderLength = 32;
    NSData *_Nullable headerData = [data subdataWithRange:NSMakeRange(0, kSqliteHeaderLength)];
    if (!headerData || headerData.length != kSqliteHeaderLength) {
        [NSException raise:@"Database database file header has unexpected length"
                    format:@"Database database file header has unexpected length: %zd", headerData.length];
    }
    NSString *kUnencryptedHeader = @"SQLite format 3\0";
    NSData *unencryptedHeaderData = [kUnencryptedHeader dataUsingEncoding:NSUTF8StringEncoding];
    BOOL isUnencrypted = [unencryptedHeaderData
        isEqualToData:[headerData subdataWithRange:NSMakeRange(0, unencryptedHeaderData.length)]];
    if (isUnencrypted) {
        DDLogVerbose(@"%@ Skipping database conversion; legacy database header already decrypted.", self.logTag);
        return NO;
    }

    return YES;
}

+ (void)convertDatabaseIfNecessary
{
    NSString *databaseFilePath = [TSStorageManager legacyDatabaseFilePath];
    [self convertDatabaseIfNecessary:databaseFilePath];
}

+ (void)convertDatabaseIfNecessary:(NSString *)databaseFilePath
{
    if (![self doesDatabaseNeedToBeConverted:databaseFilePath]) {
        return;
    }

    [self convertDatabase:(NSString *)databaseFilePath];
}

+ (nullable NSError *)convertDatabase:(NSString *)databaseFilePath
{
    OWSAssert(databaseFilePath.length > 0);

    NSError *error;
    NSData *_Nullable databasePassword = [OWSStorage tryToLoadDatabasePassword:&error];
    if (!databasePassword || error) {
        return (error
                ?: [NSError errorWithDomain:OWSOWSDatabaseConverterErrorDomain
                                       code:kCouldNotLoadDatabasePassword
                                   userInfo:nil]);
    }

    // TODO:

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

    //    - (BOOL)openDatabase
    //    {
    //        // Open the database connection.
    //        //
    //        // We use SQLITE_OPEN_NOMUTEX to use the multi-thread threading mode,
    //        // as we will be serializing access to the connection externally.
    //


    // -----------------------------------------------------------
    //
    // This block was derived from [Yapdatabase openDatabase].
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_PRIVATECACHE;
    sqlite3 *db;
    int status = sqlite3_open_v2([databaseFilePath UTF8String], &db, flags, NULL);
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

        return [NSError errorWithDomain:OWSOWSDatabaseConverterErrorDomain code:kCouldNotOpenDatabase userInfo:nil];
    }

    // -----------------------------------------------------------
    //
    // This block was derived from [Yapdatabase configureEncryptionForDatabase].
    NSData *keyData = databasePassword;

    //    //Setting the encrypted database page size
    //    if (options.cipherPageSize > 0) {
    //        char *errorMsg;
    //        NSString *pragmaCommand = [NSString stringWithFormat:@"PRAGMA cipher_page_size = %lu", (unsigned
    //                                                                                                long)options.cipherPageSize];
    //                                                                                                if
    //                                                                                                (sqlite3_exec(sqlite,
    //                                                                                                [pragmaCommand
    //                                                                                                UTF8String], NULL,
    //                                                                                                NULL,
    //                                                                                                                                               &errorMsg) != SQLITE_OK)
    //                                                                                                {
    //                                                                                                    YDBLogError(@"failed
    //                                                                                                    to set
    //                                                                                                    database
    //                                                                                                    cipher_page_size:
    //                                                                                                    %s",
    //                                                                                                    errorMsg);
    //                                                                                                    return NO;
    //                                                                                                }
    //    }
    //
    //    int status = sqlite3_key(sqlite, [keyData bytes], (int)[keyData length]);
    //    if (status != SQLITE_OK)
    //    {
    //        YDBLogError(@"Error setting SQLCipher key: %d %s", status, sqlite3_errmsg(sqlite));
    //        return NO;
    //    }
    //}
    //
    // return YES;
    //        }
    //    #endif

    return nil;
}

@end

NS_ASSUME_NONNULL_END
