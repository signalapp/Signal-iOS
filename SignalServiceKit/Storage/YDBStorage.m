//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "YDBStorage.h"
#import "OWSFileSystem.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation YDBStorage

+ (NSString *)legacyDatabaseDirPath
{
    return [OWSFileSystem appDocumentDirectoryPath];
}

+ (NSString *)sharedDataDatabaseDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"database"];
}

+ (NSString *)databaseFilename
{
    return @"Signal.sqlite";
}

+ (NSString *)databaseFilename_SHM
{
    return [self.databaseFilename stringByAppendingString:@"-shm"];
}

+ (NSString *)databaseFilename_WAL
{
    return [self.databaseFilename stringByAppendingString:@"-wal"];
}

+ (NSString *)legacyDatabaseFilePath
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)legacyDatabaseFilePath_SHM
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)legacyDatabaseFilePath_WAL
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

+ (NSString *)sharedDataDatabaseFilePath
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)sharedDataDatabaseFilePath_SHM
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)sharedDataDatabaseFilePath_WAL
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

#pragma mark -

+ (void)deleteYDBStorage
{
    [self deleteDatabaseFiles];
}

+ (void)deleteDatabaseFiles
{
    [OWSFileSystem deleteFileIfExists:self.legacyDatabaseFilePath];
    [OWSFileSystem deleteFileIfExists:self.legacyDatabaseFilePath_SHM];
    [OWSFileSystem deleteFileIfExists:self.legacyDatabaseFilePath_WAL];
    [OWSFileSystem deleteFileIfExists:self.sharedDataDatabaseFilePath];
    [OWSFileSystem deleteFileIfExists:self.sharedDataDatabaseFilePath_SHM];
    [OWSFileSystem deleteFileIfExists:self.sharedDataDatabaseFilePath_WAL];
    // NOTE: It's NOT safe to delete OWSPrimaryStorage.legacyDatabaseDirPath
    //       which is the app document dir.
    [OWSFileSystem deleteContentsOfDirectory:self.sharedDataDatabaseDirPath];
}


@end

NS_ASSUME_NONNULL_END
