//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
#import "OWSIncompleteCallsJob.h"
#import "OWSMessageReceiver.h"
#import "OWSStorage+Subclass.h"
#import "SSKEnvironment.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "YAPDBMediaGalleryFinder.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSUIDatabaseConnectionWillUpdateNotification = @"OWSUIDatabaseConnectionWillUpdateNotification";
NSString *const OWSUIDatabaseConnectionDidUpdateNotification = @"OWSUIDatabaseConnectionDidUpdateNotification";
NSString *const OWSUIDatabaseConnectionWillUpdateExternallyNotification = @"OWSUIDatabaseConnectionWillUpdateExternallyNotification";
NSString *const OWSUIDatabaseConnectionDidUpdateExternallyNotification = @"OWSUIDatabaseConnectionDidUpdateExternallyNotification";

NSString *const OWSUIDatabaseConnectionNotificationsKey = @"OWSUIDatabaseConnectionNotificationsKey";

void VerifyRegistrationsForPrimaryStorage(OWSStorage *storage, dispatch_block_t completion)
{
    OWSCAssertDebug(storage);

    [[storage newDatabaseConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (NSString *extensionName in storage.registeredExtensionNames) {
            OWSLogVerbose(@"Verifying database extension: %@", extensionName);
            YapDatabaseViewTransaction *_Nullable viewTransaction = [transaction ext:extensionName];
            if (!viewTransaction) {
                OWSCFailDebug(@"VerifyRegistrationsForPrimaryStorage missing database extension: %@", extensionName);

                [OWSStorage incrementVersionOfDatabaseExtension:extensionName];
            }
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
    }];
}

#pragma mark -

@interface OWSPrimaryStorage ()

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;
@property (nonatomic, readonly) YapDatabaseConnectionPool *dbReadPool;

@end

#pragma mark -

@implementation OWSPrimaryStorage

@synthesize uiDatabaseConnection = _uiDatabaseConnection;

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

- (instancetype)initStorage
{
    self = [super initStorage];

    if (self) {
        [self loadDatabase];

        _dbReadPool = [[YapDatabaseConnectionPool alloc] initWithDatabase:self.database];
        _dbReadWriteConnection = [self newDatabaseConnection];
        _uiDatabaseConnection = [self newDatabaseConnection];

        // Increase object cache limit. Default is 250.
        _uiDatabaseConnection.objectCacheLimit = 500;
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:self.dbNotificationObject];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModifiedExternally:)
                                                     name:YapDatabaseModifiedExternallyNotification
                                                   object:nil];

        OWSSingletonAssert();
    }

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of this class.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    // Notify observers we're about to update the database connection
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSUIDatabaseConnectionWillUpdateExternallyNotification object:self.dbNotificationObject];
    
    // Move uiDatabaseConnection to the latest commit.
    // Do so atomically, and fetch all the notifications for each commit we jump.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    // Notify observers that the uiDatabaseConnection was updated
    NSDictionary *userInfo = @{ OWSUIDatabaseConnectionNotificationsKey: notifications };
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSUIDatabaseConnectionDidUpdateExternallyNotification
                                                        object:self.dbNotificationObject
                                                      userInfo:userInfo];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");
    [self updateUIDatabaseConnectionToLatest];
}

- (void)updateUIDatabaseConnectionToLatest
{
    OWSAssertIsOnMainThread();

    // Notify observers we're about to update the database connection
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSUIDatabaseConnectionWillUpdateNotification object:self.dbNotificationObject];

    // Move uiDatabaseConnection to the latest commit.
    // Do so atomically, and fetch all the notifications for each commit we jump.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    // Notify observers that the uiDatabaseConnection was updated
    NSDictionary *userInfo = @{ OWSUIDatabaseConnectionNotificationsKey: notifications };
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSUIDatabaseConnectionDidUpdateNotification
                                                        object:self.dbNotificationObject
                                                      userInfo:userInfo];
}

- (YapDatabaseConnection *)uiDatabaseConnection
{
    OWSAssertIsOnMainThread();
    return _uiDatabaseConnection;
}

- (void)resetStorage
{
    _dbReadPool = nil;
    _uiDatabaseConnection = nil;
    _dbReadWriteConnection = nil;

    [super resetStorage];
}

- (void)runSyncRegistrations
{
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:self];

    // See comments on OWSDatabaseConnection.
    //
    // In the absence of finding documentation that can shed light on the issue we've been
    // seeing, this issue only seems to affect sync and not async registrations.  We've always
    // been opening write transactions before the async registrations complete without negative
    // consequences.
    OWSAssertDebug(!self.areSyncRegistrationsComplete);
    self.areSyncRegistrationsComplete = YES;
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(completion);
    OWSAssertDebug(self.database);

    OWSLogVerbose(@"async registrations enqueuing.");

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.
    [TSDatabaseView asyncRegisterLegacyThreadInteractionsDatabaseView:self];

    [TSDatabaseView asyncRegisterThreadInteractionsDatabaseView:self];

    [self.database
        flushExtensionRequestsWithCompletionQueue:dispatch_get_main_queue()
                                  completionBlock:^{
                                      OWSAssertIsOnMainThread();

                                      // Building this view requires TSMessageDatabaseViewExtensionName which is
                                      // registered above in asyncRegisterThreadInteractionsDatabaseView.
                                      [TSDatabaseView asyncRegisterThreadDatabaseView:self];

                                      [TSDatabaseView asyncRegisterUnreadDatabaseView:self];
                                      [self asyncRegisterExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex]
                                                          withName:[TSDatabaseSecondaryIndexes
                                                                       registerTimeStampIndexExtensionName]];

                                      [OWSMessageReceiver asyncRegisterDatabaseExtension:self];
                                      [YAPDBMessageContentJobFinder asyncRegisterDatabaseExtension:self];

                                      [TSDatabaseView asyncRegisterUnseenDatabaseView:self];
                                      [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView:self];
                                      [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView:self];
                                      [TSDatabaseView asyncRegisterPerMessageExpirationMessagesDatabaseView:self];

                                      [FullTextSearchFinder asyncRegisterDatabaseExtensionWithStorage:self];
                                      [OWSIncomingMessageFinder asyncRegisterExtensionWithPrimaryStorage:self];
                                      [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView:self];
                                      [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:self];
                                      [OWSFailedMessagesJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:self];
                                      [OWSIncompleteCallsJob asyncRegisterDatabaseExtensionsWithPrimaryStorage:self];
                                      [OWSFailedAttachmentDownloadsJob
                                          asyncRegisterDatabaseExtensionsWithPrimaryStorage:self];
                                      [YAPDBMediaGalleryFinder asyncRegisterDatabaseExtensionsWithPrimaryStorage:self];
                                      [TSDatabaseView asyncRegisterLazyRestoreAttachmentsDatabaseView:self];
                                      [YAPDBJobRecordFinderSetup asyncRegisterDatabaseExtensionObjCWithStorage:self];
                                      [YAPDBSignalAccountFinder asyncRegisterDatabaseExtensions:self];
                                      [YAPDBSignalRecipientFinder asyncRegisterDatabaseExtensions:self];

                                      [self.database
                                          flushExtensionRequestsWithCompletionQueue:dispatch_get_global_queue(
                                                                                        DISPATCH_QUEUE_PRIORITY_DEFAULT,
                                                                                        0)
                                                                    completionBlock:^{
                                                                        OWSAssertDebug(
                                                                            !self.areAsyncRegistrationsComplete);
                                                                        OWSLogVerbose(@"async registrations complete.");

                                                                        // We verify that all database views registered
                                                                        // successfully and are accessible on launch
                                                                        // _before_ "database is ready".  This ensures
                                                                        // that if a view becomes corrupted it, we
                                                                        // detect that now and increment the view
                                                                        // version, so that it will be rebuilt on next
                                                                        // launch. Otherwise, the app might crash later
                                                                        // in a place that won't increment the view
                                                                        // version.
                                                                        VerifyRegistrationsForPrimaryStorage(self, ^{
                                                                            self.areAsyncRegistrationsComplete = YES;

                                                                            completion();
                                                                        });
                                                                    }];
                                  }];
}

+ (void)protectFiles
{
    OWSLogInfo(@"Database file size: %@", [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath]);
    OWSLogInfo(@"\t SHM file size: %@", [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_SHM]);
    OWSLogInfo(@"\t WAL file size: %@", [OWSFileSystem fileSizeOfPath:self.sharedDataDatabaseFilePath_WAL]);

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
        OWSFail(@"Could not create new database directory");
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
    OWSLogInfo(@"");

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
            OWSLogInfo(@"before migrateToSharedData: %@, %@", path, [OWSFileSystem fileSizeOfPath:path]);
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
            OWSLogInfo(@"after migrateToSharedData: %@, %@", path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }

    return nil;
}

+ (NSString *)databaseFilePath
{
    OWSLogVerbose(@"databasePath: %@", OWSPrimaryStorage.sharedDataDatabaseFilePath);

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

- (YapDatabaseConnection *)dbReadConnection
{
    return self.dbReadPool.connection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
}

#pragma mark - Misc.

- (void)touchDbAsync
{
    OWSLogInfo(@"");

    // There appears to be a bug in YapDatabase that sometimes delays modifications
    // made in another process (e.g. the SAE) from showing up in other processes.
    // There's a simple workaround: a trivial write to the database flushes changes
    // made from other processes.
    [self.dbReadWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[NSUUID UUID].UUIDString forKey:@"conversation_view_noop_mod" inCollection:@"temp"];
    }];
}

@end

NS_ASSUME_NONNULL_END
