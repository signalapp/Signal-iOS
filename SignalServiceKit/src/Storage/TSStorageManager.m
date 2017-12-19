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
#import "OWSStorage+Subclass.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerExceptionName_CouldNotMoveDatabaseFile
    = @"TSStorageManagerExceptionName_CouldNotMoveDatabaseFile";
NSString *const TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
    = @"TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory";

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
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:self];
    [TSDatabaseView registerThreadInteractionsDatabaseView:self];
    [TSDatabaseView registerThreadDatabaseView:self];
    [TSDatabaseView registerUnreadDatabaseView:self];
    [self registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    [OWSMessageReceiver syncRegisterDatabaseExtension:self];
    [OWSBatchMessageProcessor syncRegisterDatabaseExtension:self];

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

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.
    [TSDatabaseView asyncRegisterUnseenDatabaseView:self];
    [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView:self];
    [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView:self];

    // Register extensions which aren't essential for rendering threads async.
    [OWSIncomingMessageFinder asyncRegisterExtensionWithStorageManager:self];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView:self];
    [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:self];
    [OWSFailedMessagesJob asyncRegisterDatabaseExtensionsWithStorageManager:self];
    [OWSFailedAttachmentDownloadsJob asyncRegisterDatabaseExtensionsWithStorageManager:self];

    // Block until all async registrations are complete.
    [self.newDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSAssert(!self.areAsyncRegistrationsComplete);

        self.areAsyncRegistrationsComplete = YES;

        completion();
    }];
}

+ (void)protectFiles
{
    // The old database location was in the Document directory,
    // so protect the database files individually.
    [OWSFileSystem protectFileOrFolderAtPath:self.primaryDatabaseFilePath];
    [OWSFileSystem protectFileOrFolderAtPath:self.primaryDatabaseFilePath_SHM];
    [OWSFileSystem protectFileOrFolderAtPath:self.primaryDatabaseFilePath_WAL];

    // Protect the entire new database directory.
    [OWSFileSystem protectFileOrFolderAtPath:self.sharedDataDatabaseDirPath];
}

+ (NSString *)primaryDatabaseDirPath
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

+ (NSString *)primaryDatabaseFilePath
{
    return [self.primaryDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)primaryDatabaseFilePath_SHM
{
    return [self.primaryDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)primaryDatabaseFilePath_WAL
{
    return [self.primaryDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

+ (NSString *)databaseFilePath
{
    DDLogVerbose(@"databasePath: %@", TSStorageManager.primaryDatabaseFilePath);

    return self.primaryDatabaseFilePath;
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
