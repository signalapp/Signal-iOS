//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupStorage.h"

//#import "AppContext.h"
//#import "OWSAnalytics.h"
//#import "OWSBatchMessageProcessor.h"
//#import "OWSDisappearingMessagesFinder.h"
//#import "OWSFailedAttachmentDownloadsJob.h"
//#import "OWSFailedMessagesJob.h"
//#import "OWSFileSystem.h"
//#import "OWSIncomingMessageFinder.h"
//#import "OWSMessageReceiver.h"
#import "OWSStorage+Subclass.h"

//#import "TSDatabaseSecondaryIndexes.h"
//#import "TSDatabaseView.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSBackupStorageExceptionName_CouldNotCreateDatabaseDirectory
    = @"OWSBackupStorageExceptionName_CouldNotCreateDatabaseDirectory";

#pragma mark -

@interface OWSBackupStorage ()

@property (nonatomic, readonly, nullable) YapDatabaseConnection *dbConnection;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation OWSBackupStorage

//+ (instancetype)sharedManager
//{
//    static OWSBackupStorage *sharedManager = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        sharedManager = [[self alloc] initStorage];
//
//#if TARGET_OS_IPHONE
//        [OWSBackupStorage protectFiles];
//#endif
//    });
//    return sharedManager;
//}

- (instancetype)initStorage
{
    self = [super initStorage];

    if (self) {
        _dbConnection = self.newDatabaseConnection;

        OWSSingletonAssert();
    }

    return self;
}

- (void)resetStorage
{
    _dbConnection = nil;
    //    _dbReadWriteConnection = nil;

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
    // TODO:

    //    DDLogInfo(
    //        @"%@ Database file size: %@", self.logTag, [OWSFileSystem
    //        fileSizeOfPath:self.sharedDataDatabaseFilePath]);
    //    DDLogInfo(
    //        @"%@ \t SHM file size: %@", self.logTag, [OWSFileSystem
    //        fileSizeOfPath:self.sharedDataDatabaseFilePath_SHM]);
    //    DDLogInfo(
    //        @"%@ \t WAL file size: %@", self.logTag, [OWSFileSystem
    //        fileSizeOfPath:self.sharedDataDatabaseFilePath_WAL]);
    //
    //    // Protect the entire new database directory.
    //    [OWSFileSystem protectFileOrFolderAtPath:self.sharedDataDatabaseDirPath];
}

//+ (NSString *)legacyDatabaseDirPath
//{
//    return [OWSFileSystem appDocumentDirectoryPath];
//}
//
//+ (NSString *)sharedDataDatabaseDirPath
//{
//    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath]
//    stringByAppendingPathComponent:@"database"];
//
//    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
//        OWSRaiseException(
//            OWSBackupStorageExceptionName_CouldNotCreateDatabaseDirectory, @"Could not create new database
//            directory");
//    }
//    return databaseDirPath;
//}

+ (NSString *)databaseFilename
{
    return @"SignalBackup.sqlite";
}

//+ (NSString *)databaseFilename_SHM
//{
//    return [self.databaseFilename stringByAppendingString:@"-shm"];
//}
//
//+ (NSString *)databaseFilename_WAL
//{
//    return [self.databaseFilename stringByAppendingString:@"-wal"];
//}
//
//+ (NSString *)legacyDatabaseFilePath
//{
//    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
//}
//
//+ (NSString *)legacyDatabaseFilePath_SHM
//{
//    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
//}
//
//+ (NSString *)legacyDatabaseFilePath_WAL
//{
//    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
//}
//
//+ (NSString *)sharedDataDatabaseFilePath
//{
//    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
//}
//
//+ (NSString *)sharedDataDatabaseFilePath_SHM
//{
//    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
//}
//
//+ (NSString *)sharedDataDatabaseFilePath_WAL
//{
//    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
//}

//+ (NSString *)databaseFilePath
//{
//    DDLogVerbose(@"%@ databasePath: %@", self.logTag, OWSBackupStorage.sharedDataDatabaseFilePath);
//
//    return self.sharedDataDatabaseFilePath;
//}
//
//- (NSString *)databaseFilePath
//{
//    return OWSBackupStorage.databaseFilePath;
//}

//+ (YapDatabaseConnection *)dbReadConnection
//{
//    return OWSBackupStorage.sharedManager.dbReadConnection;
//}
//
//+ (YapDatabaseConnection *)dbReadWriteConnection
//{
//    return OWSBackupStorage.sharedManager.dbReadWriteConnection;
//}

@end

NS_ASSUME_NONNULL_END
