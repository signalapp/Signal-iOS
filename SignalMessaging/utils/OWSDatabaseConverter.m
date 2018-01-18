//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConverter.h"
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseConverter

+ (BOOL)doesDatabaseNeedToBeConverted
{
    NSString *databaseFilePath = [TSStorageManager legacyDatabaseFilePath];
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
    if (![self doesDatabaseNeedToBeConverted]) {
        return;
    }

    [self convertDatabase];
}

+ (void)convertDatabase
{
    // TODO:
}

@end

NS_ASSUME_NONNULL_END
