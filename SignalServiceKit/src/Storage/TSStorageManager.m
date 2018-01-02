//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import "AppContext.h"
#import "NSDate+OWS.h"
#import "NSUserDefaults+OWS.h"
#import "OWSAnalytics.h"
#import "OWSBackgroundTask.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSFileSystem.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSMessageReceiver.h"
#import "OWSPrimaryCopyStorage.h"
#import "OWSStorage+Subclass.h"
#import "TSAttachment.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "Threading.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName
    = @"NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName";
NSString *const NSUserDefaultsKey_OWSPrimaryStoragePreviousBackupDirName
    = @"NSUserDefaultsKey_OWSPrimaryStoragePreviousBackupDirName";
// NSString *const NSUserDefaultsKey_OWSPrimaryStorageLastBackupDate
//    = @"NSUserDefaultsKey_OWSPrimaryStorageLastBackupDate";

void runSyncRegistrationsForPrimaryStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:storage];
    [TSDatabaseView registerThreadInteractionsDatabaseView:storage];
    [TSDatabaseView registerThreadDatabaseView:storage];
    [TSDatabaseView registerUnreadDatabaseView:storage];
    [storage registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    [OWSMessageReceiver syncRegisterDatabaseExtension:storage];
    [OWSBatchMessageProcessor syncRegisterDatabaseExtension:storage];
}

void runAsyncRegistrationsForPrimaryStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.
    [TSDatabaseView asyncRegisterUnseenDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView:storage];

    // Register extensions which aren't essential for rendering threads async.
    [OWSIncomingMessageFinder asyncRegisterExtensionWithStorageManager:storage];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView:storage];
    [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:storage];
    [OWSFailedMessagesJob asyncRegisterDatabaseExtensionsWithStorageManager:storage];
    [OWSFailedAttachmentDownloadsJob asyncRegisterDatabaseExtensionsWithStorageManager:storage];
}

@interface TSStorageManager ()

@property (nonatomic, readonly, nullable) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly, nullable) YapDatabaseConnection *dbReadWriteConnection;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation TSStorageManager

+ (instancetype)sharedManager {
    static TSStorageManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initStorage];

#if TARGET_OS_IPHONE
        [TSStorageManager protectFiles];
#endif
    });
    return sharedManager;
}

- (instancetype)initStorage
{
    self = [super initStorage];

    if (self) {
        [self openDatabase];

        [self observeNotifications];

        _dbReadConnection = self.newDatabaseConnection;
        _dbReadWriteConnection = self.newDatabaseConnection;
#if DEBUG
        if (!CurrentAppContext().isMainApp) {
            // In the SAE, the app should only read from the primary copy database.
            self.dbReadConnection.permittedTransactions = YDB_AnyReadTransaction;
            self.dbReadWriteConnection.permittedTransactions = YDB_AnyReadTransaction;
        }
#endif

        OWSSingletonAssert();
    }

    return self;
}

- (StorageType)storageType
{
    return StorageType_Primary;
}

- (void)resetStorage
{
    _dbReadConnection = nil;
    _dbReadWriteConnection = nil;

    [super resetStorage];
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
    OWSDatabaseConnection *dbConnection = (OWSDatabaseConnection *)self.newDatabaseConnection;
    [dbConnection safeAsyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSAssert(!self.areAsyncRegistrationsComplete);

        self.areAsyncRegistrationsComplete = YES;

        completion();
    }
                              completionQueue:NULL
                              completionBlock:nil];
}

+ (void)protectFiles
{
    // The old database location was in the Document directory,
    // so protect the database files individually.
    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath];
    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath_SHM];
    [OWSFileSystem protectFileOrFolderAtPath:self.databaseFilePath_WAL];
}

+ (NSString *)databaseDirPath
{
    return [OWSFileSystem appDocumentDirectoryPath];
}

+ (NSString *)databaseFilename
{
    // We should only refer to the "original" primary database in the main app.
    OWSAssert(CurrentAppContext().isMainApp);

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

+ (nullable NSString *)lastBackupPath
{

    NSString *_Nullable copyDirName =
        [NSUserDefaults.appUserDefaults objectForKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName];
    if (!copyDirName) {
        return nil;
    }
    return [OWSPrimaryCopyStorage databaseCopyFilePathForDirName:copyDirName];
}

// In the SAE, we should use the primary database copy.
+ (NSString *)databaseFilePath
{
    NSString *filePath;
    if (CurrentAppContext().isMainApp) {
        filePath = [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename];
    } else {
        NSString *_Nullable copyDatabaseFilePath = self.lastBackupPath;
        if (!copyDatabaseFilePath || ![[NSFileManager defaultManager] fileExistsAtPath:copyDatabaseFilePath]) {
            OWSFail(@"%@ Missing last backup: %@", self.logTag, copyDatabaseFilePath);
            [NSException raise:@"TSStorageExceptionName_MissingLastBackup" format:@"Last database backup not found"];
        }
        DDLogInfo(@"%@ Using database copy: %@", self.logTag, copyDatabaseFilePath);
        filePath = copyDatabaseFilePath;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *_Nullable error;
        unsigned long long fileSize =
            [[fileManager attributesOfItemAtPath:filePath error:&error][NSFileSize] unsignedLongLongValue];
        if (error) {
            DDLogError(@"%@ Couldn't fetch database file size: %@", self.logTag, error);
        } else {
            DDLogInfo(@"%@ Database file size: %llu", self.logTag, fileSize);
        }

        [OWSFileSystem protectFileOrFolderAtPath:filePath];
    });

    return filePath;
}

+ (NSString *)databaseFilePath_SHM
{
    if (!CurrentAppContext().isMainApp) {
        return [[self lastBackupPath] stringByAppendingString:@"-shm"];
    }

    NSString *filePath = [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [OWSFileSystem protectFileOrFolderAtPath:filePath];
    });

    return filePath;
}

+ (NSString *)databaseFilePath_WAL
{
    if (!CurrentAppContext().isMainApp) {
        return [[self lastBackupPath] stringByAppendingString:@"-wal"];
    }

    NSString *filePath = [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [OWSFileSystem protectFileOrFolderAtPath:filePath];
    });

    return filePath;
}

- (NSString *)databaseFilePath
{
    return TSStorageManager.databaseFilePath;
}

- (NSString *)databaseFilePath_SHM
{
    return TSStorageManager.databaseFilePath_SHM;
}

- (NSString *)databaseFilePath_WAL
{
    return TSStorageManager.databaseFilePath_WAL;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return TSStorageManager.sharedManager.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return TSStorageManager.sharedManager.dbReadWriteConnection;
}

#pragma mark - Primary Copy


// To avoid the 0xdead10cc crashes (iOS app can't retain file lock
// on files in shared data container while suspended), the main app
// backs up its primary database to the "backup" database in the
// shared data container.
//
// The database backup mechanism provided by YapDatabase/Sqlite supports
// fast incremental backups so long as the backup copy is only modified
// by backup (e.g. doesn't "fork").
//
// The SAE _SHOULD NOT_ modify its copy, but for rigor we don't want to
// assume that we have eliminated all cases where it makes db writes, so
// we do a file-based copy of the "backup" database to the "fork" database
// and use that in the SAE. If the "fork-safe" database forks, this is
// safe; those changes will be discarded the next time we make a "fork"
// copy of the "backup" database.
//
// TODO: Alternately, we could owsFail()/throw an exception whenever
// we try to write to the primary database from the SAE.
//
// Our options:
//
// * File-based copy of database file during main app launch before database file opened.
//   NO, risks making appDidFinishLaunching too long,
// * File-based copy of database file during main app launch after database file opened.
//   NO, problematic to to lock primary database.
// * YapDatabase-based backup of primary database as part of main app launch.
//   PROBABLY.
//
// SAE might mutate and therefore fork its copy, prevent incremental backups.
// We can't replace the SAE copy while the SAE is using it.
//
// Our options:
//
// * File-based copy of backup to "fork-safe copy" on SAE launch.
// * File-based copy of backup to "fork-safe copy" on main app launch after backup.
//   Coordinate latest copy using NSUserDefaults.
//   Least developer effort, but lots of extra main app work, disk
// *

// * Don't use non-sqlite to share data.
// * Only copy a few entities like TSThread, SignalAccount.
// *

- (NSTimeInterval)databaseCopyFrequency
{
    return kDayInterval;
}

- (void)copyPrimaryDatabaseFileWithCompletion:(void (^_Nonnull)(void))completion
{
    OWSAssert(CurrentAppContext().isMainApp);
    OWSAssert(completion);

    //    NSDate *_Nullable lastBackupDate =
    //        [NSUserDefaults.appUserDefaults objectForKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDate];
    //    if (lastBackupDate && fabs(lastBackupDate.timeIntervalSinceNow) < self.databaseCopyFrequency) {
    //
    //        DDLogInfo(@"%@ Skipping backup of primary database", self.logTag);
    //
    //        dispatch_async(dispatch_get_main_queue(), completion);
    //
    //        return;
    //    }

    NSString *copyDirName = [NSUUID UUID].UUIDString;

    DDLogInfo(@"%@ Primary database copy started: %@", self.logTag, copyDirName);

    NSDate *registrationsStartDate = [NSDate new];
    OWSPrimaryCopyStorage *copyStorage = [[OWSPrimaryCopyStorage alloc] initWithDirName:copyDirName];
    [copyStorage runSyncRegistrations];
    [copyStorage runAsyncRegistrationsWithCompletion:^{

        DDLogInfo(@"%@ Primary database copy registrations completed: %@, in: %f",
            self.logTag,
            copyDirName,
            fabs(registrationsStartDate.timeIntervalSinceNow));

        NSDate *backupStartDate = [NSDate new];
        [self copyDatabaseToStorage:copyStorage
                         completion:^(NSError *_Nullable error) {
                             OWSAssertIsOnMainThread();

                             if (error) {
                                 DDLogError(@"%@ Primary database copy failed: %@", self.logTag, error);
                                 return;
                             }
                             DDLogInfo(@"%@ Primary database copy completed: %@, in: %f",
                                 self.logTag,
                                 copyDirName,
                                 fabs(backupStartDate.timeIntervalSinceNow));

                             // Rotate the previous database dir name, if possible.
                             NSString *_Nullable previousBackupDirName = [NSUserDefaults.appUserDefaults
                                 objectForKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName];
                             if (previousBackupDirName) {
                                 [NSUserDefaults.appUserDefaults
                                     setObject:previousBackupDirName
                                        forKey:NSUserDefaultsKey_OWSPrimaryStoragePreviousBackupDirName];
                             }

                             [NSUserDefaults.appUserDefaults
                                 setObject:copyDirName
                                    forKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName];
                             //                             [NSUserDefaults.appUserDefaults
                             //                                 setObject:backupStartDate
                             //                                    forKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDate];
                             [NSUserDefaults.appUserDefaults synchronize];

                             dispatch_async(dispatch_get_main_queue(), completion);

                             [self cleanUpDatabaseCopies];
                         }];
    }];
}

- (void)copyDatabaseToStorage:(OWSPrimaryCopyStorage *)copyStorage
                   completion:(void (^_Nonnull)(NSError *_Nullable))completionParameter
{
    // Wrap copy in a background task.
    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    void (^completion)(NSError *_Nullable) = ^(NSError *_Nullable error) {
        DispatchMainThreadSafe(^{
            completionParameter(error);

            backgroundTask = nil;
        });
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        YapDatabaseConnection *srcDBConnection = self.newDatabaseConnection;
        YapDatabaseConnection *dstDBConnection = copyStorage.newDatabaseConnection;

        NSArray<NSString *> *collectionsToIgnore = @[
            TSInteraction.collection,
            TSAttachment.collection,
        ];
        NSMutableArray<NSString *> *allCollections = [NSMutableArray new];
        [srcDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [allCollections addObjectsFromArray:transaction.allCollections];
        }];
        for (NSString *collection in allCollections) {
            if ([collectionsToIgnore containsObject:collection]) {
                DDLogVerbose(@"%@ Ignoring: %@", self.logTag, collection);
                continue;
            }
            [OWSStorage copyCollection:collection
                       srcDBConnection:srcDBConnection
                       dstDBConnection:dstDBConnection
                            valueClass:[NSObject class]];
        }

        completion(nil);
    });
}

- (void)cleanUpDatabaseCopies
{
    // We've just completed a database copy.  Try to delete obsolete database copies.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *_Nullable lastBackupDirName =
            [NSUserDefaults.appUserDefaults objectForKey:NSUserDefaultsKey_OWSPrimaryStorageLastBackupDirName];
        NSString *_Nullable previousBackupDirName =
            [NSUserDefaults.appUserDefaults objectForKey:NSUserDefaultsKey_OWSPrimaryStoragePreviousBackupDirName];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *_Nullable error;
        for (NSString *backupDirName in
            [fileManager contentsOfDirectoryAtPath:OWSPrimaryCopyStorage.databaseCopiesDirPath error:&error]) {
            DDLogVerbose(@"%@ Considering database copy: %@", self.logTag, backupDirName);
            if (lastBackupDirName && [lastBackupDirName isEqualToString:backupDirName]) {
                // Don't delete the current backup.
                continue;
            }
            if (previousBackupDirName && [previousBackupDirName isEqualToString:backupDirName]) {
                // Don't delete the last backup, the SAE may still be using it.
                continue;
            }
            NSString *backupDirPath =
                [OWSPrimaryCopyStorage.databaseCopiesDirPath stringByAppendingPathComponent:backupDirName];
            [fileManager removeItemAtPath:backupDirPath error:&error];
            if (error) {
                DDLogInfo(@"%@ Couldn't delete database copy: %@, %@", self.logTag, backupDirPath, error);
            } else {
                DDLogVerbose(@"%@ Deleted database copy: %@, %@", self.logTag, backupDirPath, error);
            }
        }
        if (error) {
            DDLogInfo(@"%@ Couldn't list database copies dir contents: %@", self.logTag, error);
        }
    });
}

#pragma mark - OWSDatabaseConnectionDelegate

- (void)readWriteTransactionWillBegin
{
    if (!CurrentAppContext().isMainApp) {
        OWSFail(@"%@ Should not write to primary database from SAE.", self.logTag);

        [NSException raise:@"OWSStorageExceptionName_UnsafeWriteToBackupDB"
                    format:@"Should not write to primary database from SAE."];
    } else {
        [super readWriteTransactionWillBegin];
    }
}

@end

NS_ASSUME_NONNULL_END
