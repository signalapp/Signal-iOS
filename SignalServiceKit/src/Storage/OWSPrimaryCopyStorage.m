//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryCopyStorage.h"

//#import "AppContext.h"
#import "OWSFileSystem.h"
#import "OWSStorage+Subclass.h"

//#import "TSDatabaseSecondaryIndexes.h"
//#import "TSDatabaseView.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryCopyStorageExceptionName_CouldNotCreateDatabaseDirectory
    = @"OWSPrimaryCopyStorageExceptionName_CouldNotCreateDatabaseDirectory";

#pragma mark -

@interface OWSPrimaryCopyStorage ()

@property (atomic) NSString *dirName;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation OWSPrimaryCopyStorage

- (instancetype)initWithDirName:(NSString *)dirName
{
    self = [super initStorage];

    if (self) {
        self.dirName = dirName;

        [self openDatabase];

        [self observeNotifications];

        OWSSingletonAssert();
    }

    return self;
}

- (StorageType)storageType
{
    return StorageType_PrimaryCopy;
}

- (void)runSyncRegistrations
{
    runSyncRegistrationsForPrimaryStorage(self);

    // See comments on OWSDatabaseConnection.
    //
    // In the absence of finding documentation that can shed light on the issue we've been
    // seeing, this issue only seems to affect sync and not async registrations.  We've always
    // been opening write transactions before the async registrations complete without negative
    // consequences.
    OWSAssert(!self.areSyncRegistrationsComplete);
    self.areSyncRegistrationsComplete = YES;
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWSAssert(completion);

    runAsyncRegistrationsForPrimaryStorage(self);

    // Block until all async registrations are complete.
    [self.newDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSAssert(!self.areAsyncRegistrationsComplete);

        self.areAsyncRegistrationsComplete = YES;

        completion();
    }];
}

//- (void)protectFiles
//{
//    // The old database location was in the Document directory,
//    // so protect the database files individually.
//    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath];
//    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath_SHM];
//    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath_WAL];
//
//    // Protect the entire new database directory.
//    [OWSFileSystem protectFileOrFolderAtPath:self.sharedDataDatabaseDirPath];
//}

//+ (NSString *)sharedDataDatabaseDirPath
//{
//    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath]
//    stringByAppendingPathComponent:@"database"];
//
//    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
//        [NSException raise:OWSPrimaryCopyStorageExceptionName_CouldNotCreateDatabaseDirectory
//                    format:@"Could not create new database directory"];
//    }
//    return databaseDirPath;
//}

+ (NSString *)databaseCopyFilename
{
    return @"Signal.sqlite";
}

// The directory in the shared data container that contains the database copies.
//
// Each database copy resides in a subdirectory so that SHM and WAL files are
// removed in unison with their database file.
+ (NSString *)databaseCopiesDirPath
{
    NSString *dirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"PrimaryCopies"];

    if (![OWSFileSystem ensureDirectoryExists:dirPath]) {
        [NSException raise:OWSPrimaryCopyStorageExceptionName_CouldNotCreateDatabaseDirectory
                    format:@"Could not create new database directory"];
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [OWSFileSystem protectFileOrFolderAtPath:dirPath];
    });

    return dirPath;
}

+ (NSString *)databaseCopyFilePathForDirName:(NSString *)dirName
{
    OWSAssert(dirName.length > 0);

    NSString *copyDirPath = [self.databaseCopiesDirPath stringByAppendingPathComponent:dirName];
    if (![OWSFileSystem ensureDirectoryExists:copyDirPath]) {
        [NSException raise:OWSPrimaryCopyStorageExceptionName_CouldNotCreateDatabaseDirectory
                    format:@"Could not create new database copy directory"];
    }

    NSString *copyDatabaseFilePath = [copyDirPath stringByAppendingPathComponent:self.databaseCopyFilename];
    return copyDatabaseFilePath;
}

//+ (NSString *)databaseFilename
//{
//    return @"Primary-Copy2.sqlite";
//}
//
//+ (NSString *)databaseFilename_SHM
//{
//    return [self.databaseFilename stringByAppendingString:@"-shm"];
//}
//
//+ (NSString *)databaseFilename_WAL
//{
//    return [self.databaseFilename stringByAppendingString:@"-wal"];
//}

- (NSString *)databaseFilePath
{
    return [OWSPrimaryCopyStorage databaseCopyFilePathForDirName:self.dirName];
}

- (NSString *)databaseFilePath_SHM
{
    return [self.databaseFilePath stringByAppendingString:@"-shm"];
}

- (NSString *)databaseFilePath_WAL
{
    return [self.databaseFilePath stringByAppendingString:@"-wal"];
}

//- (NSString *)databaseFilePath
//{
//    return OWSPrimaryCopyStorage.databaseFilePath;
//}
//
//- (NSString *)databaseFilePath_SHM
//{
//    return OWSPrimaryCopyStorage.databaseFilePath_SHM;
//}
//
//- (NSString *)databaseFilePath_WAL
//{
//    return OWSPrimaryCopyStorage.databaseFilePath_WAL;
//}

@end

NS_ASSUME_NONNULL_END
