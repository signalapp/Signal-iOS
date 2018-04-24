//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"
#import "AppContext.h"
#import "OWSAnalytics.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSFileSystem.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSMediaGalleryFinder.h"
#import "OWSMessageReceiver.h"
#import "OWSStorage+Subclass.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageExceptionName_CouldNotCreateDatabaseDirectory
    = @"TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory";

void RunSyncRegistrationsForStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:storage];
}

void RunAsyncRegistrationsForStorage(OWSStorage *storage, dispatch_block_t completion)
{
    OWSCAssert(storage);
    OWSCAssert(completion);

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.

    [TSDatabaseView asyncRegisterThreadInteractionsDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadDatabaseView:storage];
    [TSDatabaseView asyncRegisterUnreadDatabaseView:storage];
    [storage asyncRegisterExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex]
                           withName:[self registerTimeStampIndexExtensionName]];
    [OWSMessageReceiver asyncRegisterDatabaseExtension:storage];
    [OWSBatchMessageProcessor asyncRegisterDatabaseExtension:storage];

    [TSDatabaseView asyncRegisterUnseenDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView:storage];
    [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView:storage];

    // Register extensions which aren't essential for rendering threads async.
    [OWSIncomingMessageFinder asyncRegisterExtensionWithPrimaryStorage:storage];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView:storage];
    [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:storage];
    [OWSFailedMessagesJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
    [OWSFailedAttachmentDownloadsJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
    [OWSMediaGalleryFinder asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
    // NOTE: Always pass the completion to the _LAST_ of the async database
    // view registrations.
    [TSDatabaseView asyncRegisterLazyRestoreAttachmentsDatabaseView:storage completion:completion];
}

extern NSString *const TSThreadOutgoingMessageDatabaseViewExtensionName;
extern NSString *const TSUnseenDatabaseViewExtensionName;
extern NSString *const TSThreadSpecialMessagesDatabaseViewExtensionName;

NSArray<NSString *> *ExtensionNamesForPrimaryStorage()
{
    // This should 1:1 correspond to the database view registrations
    // done in RunSyncRegistrationsForStorage() and
    // RunAsyncRegistrationsForStorage().
    return @[
        // We don't need to verify the cross process notifier.
        // [TSDatabaseView registerCrossProcessNotifier:storage];

        // [TSDatabaseView asyncRegisterThreadInteractionsDatabaseView:storage];
        TSMessageDatabaseViewExtensionName,

        // [TSDatabaseView asyncRegisterThreadDatabaseView:storage];
        TSThreadDatabaseViewExtensionName,

        // [TSDatabaseView asyncRegisterUnreadDatabaseView:storage];
        TSUnreadDatabaseViewExtensionName,

        // [storage asyncRegisterExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:[self
        // registerTimeStampIndexExtensionName]];
        [self registerTimeStampIndexExtensionName],

        // [OWSMessageReceiver asyncRegisterDatabaseExtension:storage];
        [OWSMessageReceiver databaseExtensionName],

        // [OWSBatchMessageProcessor asyncRegisterDatabaseExtension:storage];
        [OWSBatchMessageProcessor databaseExtensionName],

        // [TSDatabaseView asyncRegisterUnseenDatabaseView:storage];
        TSUnseenDatabaseViewExtensionName,

        // [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView:storage];
        TSThreadOutgoingMessageDatabaseViewExtensionName,

        // [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView:storage];
        TSThreadSpecialMessagesDatabaseViewExtensionName,

        // [OWSIncomingMessageFinder asyncRegisterExtensionWithPrimaryStorage:storage];
        [OWSIncomingMessageFinder databaseExtensionName],

        // [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView:storage];
        TSSecondaryDevicesDatabaseViewExtensionName,

        // [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:storage];
        [OWSDisappearingMessagesFinder databaseExtensionName],

        // [OWSFailedMessagesJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
        [OWSFailedMessagesJob databaseExtensionName],

        // [OWSFailedAttachmentDownloadsJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
        [OWSFailedAttachmentDownloadsJob databaseExtensionName],

        // [OWSMediaGalleryFinder asyncRegisterDatabaseExtensionsWithPrimaryStorage:storage];
        [OWSMediaGalleryFinder databaseExtensionName],

        // NOTE: Always pass the completion to the _LAST_ of the async database
        // view registrations.
        // [TSDatabaseView asyncRegisterLazyRestoreAttachmentsDatabaseView:storage completion:completion];
        TSLazyRestoreAttachmentsDatabaseViewExtensionName,
    ];
}

void VerifyRegistrationsForPrimaryStorage(OWSStorage *storage)
{
    OWSCAssert(storage);

    [[storage newDatabaseConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (NSString *extensionName in ExtensionNamesForPrimaryStorage()) {
            YapDatabaseViewTransaction *_Nullable viewTransaction = [transaction ext:extensionName];
            if (!viewTransaction) {
                OWSProdLogAndCFail(
                    @"VerifyRegistrationsForPrimaryStorage missing database extension: %@", extensionName);

                [OWSStorage incrementVersionOfDatabaseExtension:extensionName];
            }
        }
    }];
}

#pragma mark -

@interface OWSPrimaryStorage ()

@property (nonatomic, readonly, nullable) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly, nullable) YapDatabaseConnection *dbReadWriteConnection;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation OWSPrimaryStorage

+ (instancetype)sharedManager
{
    static OWSPrimaryStorage *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initStorage];

#if TARGET_OS_IPHONE
        [OWSPrimaryStorage protectFiles];
#endif
    });
    return sharedManager;
}

- (instancetype)initStorage
{
    self = [super initStorage];

    if (self) {
        [self loadDatabase];

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
    RunSyncRegistrationsForStorage(self);

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

    DDLogVerbose(@"%@ async registrations enqueuing.", self.logTag);

    RunAsyncRegistrationsForStorage(self, ^{
        OWSAssertIsOnMainThread();

        OWSAssert(!self.areAsyncRegistrationsComplete);

        DDLogVerbose(@"%@ async registrations complete.", self.logTag);

        self.areAsyncRegistrationsComplete = YES;

        completion();

        [self verifyDatabaseViews];
    });
}

- (void)verifyDatabaseViews
{
    VerifyRegistrationsForPrimaryStorage(self);
}

+ (void)protectFiles
{
    DDLogInfo(
        @"%@ Database file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath]);
    DDLogInfo(
        @"%@ \t SHM file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_SHM]);
    DDLogInfo(
        @"%@ \t WAL file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_WAL]);

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
            OWSPrimaryStorageExceptionName_CouldNotCreateDatabaseDirectory, @"Could not create new database directory");
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

+ (nullable NSError *)migrateToSharedData
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

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
            DDLogInfo(@"%@ before migrateToSharedData: %@, %@", self.logTag, path, [OWSFileSystem fileSizeOfPath:path]);
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

    NSError *_Nullable error = nil;
    if ([fileManager fileExistsAtPath:self.legacyDatabaseFilePath] &&
        [fileManager fileExistsAtPath:self.sharedDataDatabaseFilePath]) {
        // In the case that we have a "database conflict" (i.e. database files
        // in the src and dst locations), ensure database integrity by renaming
        // all of the dst database files.
        for (NSString *filePath in @[
                 self.sharedDataDatabaseFilePath,
                 self.sharedDataDatabaseFilePath_SHM,
                 self.sharedDataDatabaseFilePath_WAL,
             ]) {
            error = [OWSFileSystem renameFilePathUsingRandomExtension:filePath];
            if (error) {
                return error;
            }
        }
    }

    error =
        [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath sharedDataFilePath:self.sharedDataDatabaseFilePath];
    if (error) {
        return error;
    }
    error = [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_SHM
                        sharedDataFilePath:self.sharedDataDatabaseFilePath_SHM];
    if (error) {
        return error;
    }
    error = [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_WAL
                        sharedDataFilePath:self.sharedDataDatabaseFilePath_WAL];
    if (error) {
        return error;
    }

    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            DDLogInfo(@"%@ after migrateToSharedData: %@, %@", self.logTag, path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }

    return nil;
}

+ (NSString *)databaseFilePath
{
    DDLogVerbose(@"%@ databasePath: %@", self.logTag, OWSPrimaryStorage.sharedDataDatabaseFilePath);

    return self.sharedDataDatabaseFilePath;
}

+ (NSString *)databaseFilePath_SHM
{
    return self.sharedDataDatabaseFilePath_SHM;
}

+ (NSString *)databaseFilePath_WAL
{
    return self.sharedDataDatabaseFilePath_WAL;
}

- (NSString *)databaseFilePath
{
    return OWSPrimaryStorage.databaseFilePath;
}

- (NSString *)databaseFilePath_SHM
{
    return OWSPrimaryStorage.databaseFilePath_SHM;
}

- (NSString *)databaseFilePath_WAL
{
    return OWSPrimaryStorage.databaseFilePath_WAL;
}

- (NSString *)databaseFilename_SHM
{
    return OWSPrimaryStorage.databaseFilename_SHM;
}

- (NSString *)databaseFilename_WAL
{
    return OWSPrimaryStorage.databaseFilename_WAL;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
}

@end

NS_ASSUME_NONNULL_END
