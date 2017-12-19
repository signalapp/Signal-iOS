//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import "OWSAnalytics.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSFileSystem.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSMessageReceiver.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseRelationship.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerExceptionName_CouldNotMoveDatabaseFile
    = @"TSStorageManagerExceptionName_CouldNotMoveDatabaseFile";
NSString *const TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
    = @"TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory";

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

- (void)setupDatabaseWithSafeBlockingMigrations:(void (^_Nonnull)(void))safeBlockingMigrationsBlock
{
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier];
    [TSDatabaseView registerThreadInteractionsDatabaseView];
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];
    [self registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    [OWSMessageReceiver syncRegisterDatabaseExtension:self];
    [OWSBatchMessageProcessor syncRegisterDatabaseExtension:self];

    // See comments on OWSDatabaseConnection.
    //
    // In the absence of finding documentation that can shed light on the issue we've been
    // seeing, this issue only seems to affect sync and not async registrations.  We've always
    // been opening write transactions before the async registrations complete without negative
    // consequences.
    [self setDatabaseInitialized];

    // Run the blocking migrations.
    //
    // These need to run _before_ the async registered database views or
    // they will block on them, which (in the upgrade case) can block
    // return of appDidFinishLaunching... which in term can cause the
    // app to crash on launch.
    safeBlockingMigrationsBlock();

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.
    [TSDatabaseView asyncRegisterUnseenDatabaseView];
    [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView];
    [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView];

    // Register extensions which aren't essential for rendering threads async.
    [[OWSIncomingMessageFinder new] asyncRegisterExtension];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView];
    [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:self];
    OWSFailedMessagesJob *failedMessagesJob = [[OWSFailedMessagesJob alloc] initWithStorageManager:self];
    [failedMessagesJob asyncRegisterDatabaseExtensions];
    OWSFailedAttachmentDownloadsJob *failedAttachmentDownloadsMessagesJob =
        [[OWSFailedAttachmentDownloadsJob alloc] initWithStorageManager:self];
    [failedAttachmentDownloadsMessagesJob asyncRegisterDatabaseExtensions];

    // NOTE: [TSDatabaseView asyncRegistrationCompletion] ensures that
    // DatabaseViewRegistrationCompleteNotification is not fired until all
    // of the async registrations are complete.
    [TSDatabaseView asyncRegistrationCompletion];
}

+ (void)protectFiles
{
    // The old database location was in the Document directory,
    // so protect the database files individually.
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath];
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath_SHM];
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath_WAL];

    // Protect the entire new database directory.
    [OWSFileSystem protectFolderAtPath:self.sharedDataDatabaseDirPath];
}

- (BOOL)userSetPassword {
    return FALSE;
}

+ (NSString *)legacyDatabaseDirPath
{
    return [OWSFileSystem appDocumentDirectoryPath];
}

+ (NSString *)sharedDataDatabaseDirPath
{
    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"database"];

    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
        [NSException raise:TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
                    format:@"Could not create new database directory"];
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
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath
                sharedDataFilePath:self.sharedDataDatabaseFilePath
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_SHM
                sharedDataFilePath:self.sharedDataDatabaseFilePath_SHM
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_WAL
                sharedDataFilePath:self.sharedDataDatabaseFilePath_WAL
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
}

- (NSString *)dbPath
{
    DDLogVerbose(@"databasePath: %@", TSStorageManager.sharedDataDatabaseFilePath);

    return TSStorageManager.sharedDataDatabaseFilePath;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return TSStorageManager.sharedManager.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return TSStorageManager.sharedManager.dbReadWriteConnection;
}

- (void)deleteDatabaseFile
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];
    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }
}

@end

NS_ASSUME_NONNULL_END
