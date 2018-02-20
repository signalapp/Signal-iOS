//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import "AppContext.h"
#import "OWSAnalytics.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSFileSystem.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSMessageReceiver.h"
#import "OWSStorage+Subclass.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerExceptionName_CouldNotMoveDatabaseFile
    = @"TSStorageManagerExceptionName_CouldNotMoveDatabaseFile";
NSString *const TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
    = @"TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory";

void runSyncRegistrationsForStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:storage];
}

void runAsyncRegistrationsForStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.

    [TSDatabaseView asyncRegisterThreadInteractionsDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadDatabaseView:storage];
    [TSDatabaseView asyncRegisterUnreadDatabaseView:storage];
    [storage asyncRegisterExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    [OWSMessageReceiver asyncRegisterDatabaseExtension:storage];
    [OWSBatchMessageProcessor asyncRegisterDatabaseExtension:storage];

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

#pragma mark -
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
        _dbReadConnection = self.newDatabaseConnection;
        _dbReadWriteConnection = self.newDatabaseConnection;

        OWSSingletonAssert();
    }

    return self;
}

- (void)resetStorage
{
    _dbReadConnection = nil;
    _dbReadWriteConnection = nil;

    [super resetStorage];
}

- (void)runSyncRegistrations
{
    runSyncRegistrationsForStorage(self);

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

    runAsyncRegistrationsForStorage(self);

    DDLogVerbose(@"%@ async registrations enqueued.", self.logTag);

    // Block until all async registrations are complete.
    //
    // NOTE: This has to happen on the "registration connection" for this
    //       database.
    YapDatabaseConnection *dbConnection = self.registrationConnection;
    OWSAssert(self.registrationConnection);
    [dbConnection flushTransactionsWithCompletionQueue:dispatch_get_main_queue()
                                       completionBlock:^{
                                           OWSAssert(!self.areAsyncRegistrationsComplete);

                                           DDLogVerbose(@"%@ async registrations complete.", self.logTag);

                                           self.areAsyncRegistrationsComplete = YES;

                                           completion();
                                       }];
}

+ (void)protectFiles
{
    DDLogInfo(@"%@ Database file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath]);
    DDLogInfo(@"%@ \t SHM file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_SHM]);
    DDLogInfo(@"%@ \t WAL file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_WAL]);

    // Protect the entire new database directory.
    [OWSFileSystem protectFileOrFolderAtPath:self.sharedDataDatabaseDirPath];
}

+ (NSString *)legacyDatabaseDirPath
{
    return [OWSFileSystem appDocumentDirectoryPath];
}

+ (NSString *)sharedDataDatabaseDirPath
{
    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"database"];

    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
        OWSRaiseException(
            TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory, @"Could not create new database directory");
    }
    return databaseDirPath;
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

+ (void)migrateToSharedData
{
    // Given how sensitive this migration is, we verbosely
    // log the contents of all involved paths before and after.
    NSArray<NSString *> *paths = @[
        self.legacyDatabaseFilePath,
        self.legacyDatabaseFilePath_SHM,
        self.legacyDatabaseFilePath_WAL,
        self.sharedDataDatabaseFilePath,
        self.sharedDataDatabaseFilePath_SHM,
        self.sharedDataDatabaseFilePath_WAL,
    ];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            DDLogInfo(@"%@ migrateToSharedData before %@: %@", self.logTag, path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }

    // We protect the db files here, which is somewhat redundant with what will happen in
    // `moveAppFilePath:` which also ensures file protection.
    // However that method dispatches async, since it can take a while with large attachment directories.
    //
    // Since we only have three files here it'll be quick to do it sync, and we want to make
    // sure it happens as part of the migration.
    //
    // FileProtection attributes move with the file, so we do it on the legacy files before moving
    // them.
    [OWSFileSystem protectFileOrFolderAtPath:self.legacyDatabaseFilePath];
    [OWSFileSystem protectFileOrFolderAtPath:self.legacyDatabaseFilePath_SHM];
    [OWSFileSystem protectFileOrFolderAtPath:self.legacyDatabaseFilePath_WAL];

    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath
                sharedDataFilePath:self.sharedDataDatabaseFilePath
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_SHM
                sharedDataFilePath:self.sharedDataDatabaseFilePath_SHM
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_WAL
                sharedDataFilePath:self.sharedDataDatabaseFilePath_WAL
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];

    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            DDLogInfo(@"%@ migrateToSharedData after %@: %@", self.logTag, path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }
}

+ (NSString *)databaseFilePath
{
    DDLogVerbose(@"%@ databasePath: %@", self.logTag, TSStorageManager.sharedDataDatabaseFilePath);

    return self.sharedDataDatabaseFilePath;
}

- (NSString *)databaseFilePath
{
    return TSStorageManager.databaseFilePath;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return TSStorageManager.sharedManager.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return TSStorageManager.sharedManager.dbReadWriteConnection;
}

@end

NS_ASSUME_NONNULL_END
