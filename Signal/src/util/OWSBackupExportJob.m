//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExportJob.h"
#import "OWSDatabaseMigration.h"
#import "Signal-Swift.h"
#import "zlib.h"
#import <SSZipArchive/SSZipArchive.h>
#import <SignalServiceKit/NSData+Base64.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBackupStorage.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/Threading.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabasePrivate.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ExportDatabaseKeySpec = @"kOWSBackup_ExportDatabaseKeySpec";

@interface YapDatabase (OWSBackupExportJob)

- (void)flushInternalQueue;
- (void)flushCheckpointQueue;

@end

#pragma mark -

@interface OWSStorageReference : NSObject

@property (nonatomic, nullable) OWSStorage *storage;

@end

#pragma mark -

@implementation OWSStorageReference

@end

#pragma mark -

// TODO: This implementation is a proof-of-concept and
// isn't production ready.
@interface OWSExportStream : NSObject

@property (nonatomic) NSString *dataFilePath;

@property (nonatomic) NSString *zipFilePath;

@property (nonatomic, nullable) NSFileHandle *fileHandle;

@property (nonatomic, nullable) SSZipArchive *zipFile;

@end

#pragma mark -

@implementation OWSExportStream

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [self.fileHandle closeFile];

    if (self.zipFile) {
        if (![self.zipFile close]) {
            DDLogError(@"%@ couldn't close to database snapshot zip.", self.logTag);
        }
    }
}

+ (OWSExportStream *)exportStreamWithName:(NSString *)filename jobTempDirPath:(NSString *)jobTempDirPath
{
    OWSAssert(filename.length > 0);
    OWSAssert(jobTempDirPath.length > 0);

    OWSExportStream *exportStream = [OWSExportStream new];
    exportStream.dataFilePath = [jobTempDirPath stringByAppendingPathComponent:filename];
    exportStream.zipFilePath = [exportStream.dataFilePath stringByAppendingPathExtension:@"zip"];
    if (![exportStream open]) {
        return nil;
    }
    return exportStream;
}

- (BOOL)open
{
    if (![[NSFileManager defaultManager] createFileAtPath:self.dataFilePath contents:nil attributes:nil]) {
        OWSProdLogAndFail(@"%@ Could not create database snapshot stream.", self.logTag);
        return NO;
    }
    if (![OWSFileSystem protectFileOrFolderAtPath:self.dataFilePath]) {
        OWSProdLogAndFail(@"%@ Could not protect database snapshot stream.", self.logTag);
        return NO;
    }
    NSError *error;
    self.fileHandle = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:self.dataFilePath] error:&error];
    if (!self.fileHandle || error) {
        OWSProdLogAndFail(@"%@ Could not open database snapshot stream: %@.", self.logTag, error);
        return NO;
    }
    return YES;
}

- (BOOL)writeObject:(TSYapDatabaseObject *)object
{
    OWSAssert(object);
    OWSAssert(self.fileHandle);

    NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:object];
    if (!data) {
        OWSProdLogAndFail(@"%@ couldn't serialize database object: %@", self.logTag, [object class]);
        return NO;
    }

    // We use a fixed width data type.
    unsigned int dataLength = (unsigned int)data.length;
    NSData *dataLengthData = [NSData dataWithBytes:&dataLength length:sizeof(dataLength)];
    [self.fileHandle writeData:dataLengthData];
    [self.fileHandle writeData:data];
    return YES;
}

- (BOOL)closeAndZipData
{
    [self.fileHandle closeFile];
    self.fileHandle = nil;

    self.zipFile = [[SSZipArchive alloc] initWithPath:self.zipFilePath];
    if (!self.zipFile) {
        OWSProdLogAndFail(@"%@ Could not create database snapshot zip.", self.logTag);
        return NO;
    }
    if (![self.zipFile open]) {
        OWSProdLogAndFail(@"%@ Could not open database snapshot zip.", self.logTag);
        return NO;
    }

    BOOL success = [self.zipFile writeFileAtPath:self.dataFilePath
                                    withFileName:@"payload"
                                compressionLevel:Z_BEST_COMPRESSION
                                        password:nil
                                             AES:NO];
    if (!success) {
        OWSProdLogAndFail(@"%@ Could not write to database snapshot zip.", self.logTag);
        return NO;
    }

    if (![self.zipFile close]) {
        DDLogError(@"%@ couldn't close database snapshot zip.", self.logTag);
        return NO;
    }
    self.zipFile = nil;

    if (![OWSFileSystem protectFileOrFolderAtPath:self.zipFilePath]) {
        DDLogError(@"%@ could not protect database snapshot zip.", self.logTag);
    }

    DDLogInfo(@"%@ wrote database snapshot zip: %@ (%@ -> %@)",
        self.logTag,
        self.zipFilePath.lastPathComponent,
        [OWSFileSystem fileSizeOfPath:self.dataFilePath],
        [OWSFileSystem fileSizeOfPath:self.zipFilePath]);

    return YES;
}

@end

#pragma mark -

@interface OWSAttachmentExport : NSObject

@property (nonatomic, weak) id<OWSBackupJobDelegate> delegate;
@property (nonatomic) NSString *jobTempDirPath;
@property (nonatomic) NSString *attachmentId;
@property (nonatomic) NSString *attachmentFilePath;
@property (nonatomic, nullable) NSString *tempFilePath;
@property (nonatomic, nullable) NSString *relativeFilePath;

@end

#pragma mark -

@implementation OWSAttachmentExport

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    DDLogVerbose(@"Dealloc: %@", self.class);

    // Delete temporary file ASAP.
    if (self.tempFilePath) {
        [OWSFileSystem deleteFileIfExists:self.tempFilePath];
    }
}

// On success, tempFilePath will be non-nil.
- (void)prepareForUpload
{
    OWSAssert(self.jobTempDirPath.length > 0);
    OWSAssert(self.attachmentId.length > 0);
    OWSAssert(self.attachmentFilePath.length > 0);

    NSString *attachmentsDirPath = [TSAttachmentStream attachmentsFolder];
    if (![self.attachmentFilePath hasPrefix:attachmentsDirPath]) {
        DDLogError(@"%@ attachment has unexpected path.", self.logTag);
        OWSFail(@"%@ attachment has unexpected path: %@", self.logTag, self.attachmentFilePath);
        return;
    }
    NSString *relativeFilePath = [self.attachmentFilePath substringFromIndex:attachmentsDirPath.length];
    NSString *pathSeparator = @"/";
    if ([relativeFilePath hasPrefix:pathSeparator]) {
        relativeFilePath = [relativeFilePath substringFromIndex:pathSeparator.length];
    }
    self.relativeFilePath = relativeFilePath;

    NSString *_Nullable tempFilePath = [OWSBackupExportJob encryptFileAsTempFile:self.attachmentFilePath
                                                                  jobTempDirPath:self.jobTempDirPath
                                                                        delegate:self.delegate];
    if (!tempFilePath) {
        DDLogError(@"%@ attachment could not be encrypted.", self.logTag);
        OWSFail(@"%@ attachment could not be encrypted: %@", self.logTag, self.attachmentFilePath);
        return;
    }
    self.tempFilePath = tempFilePath;
}

@end

#pragma mark -

@interface OWSBackupExportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

@property (nonatomic) NSMutableArray<NSString *> *databaseFilePaths;
// A map of "record name"-to-"file name".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *databaseRecordMap;

// A map of "attachment id"-to-"local file path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *attachmentFilePathMap;
// A map of "record name"-to-"file relative path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *attachmentRecordMap;

@property (nonatomic, nullable) NSString *manifestFilePath;
@property (nonatomic, nullable) NSString *manifestRecordName;

@end

#pragma mark -

@implementation OWSBackupExportJob

- (void)startAsync
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self updateProgressWithDescription:nil progress:nil];

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI checkCloudKitAccessWithCompletion:^(BOOL hasAccess) {
        if (hasAccess) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf start];
            });
        }
    }];
}

- (void)start
{
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CONFIGURATION",
                                            @"Indicates that the backup export is being configured.")
                               progress:nil];

    __weak OWSBackupExportJob *weakSelf = self;
    [self configureExport:^(BOOL configureExportSuccess) {
        if (!configureExportSuccess) {
            [self failWithErrorDescription:
                      NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                          @"Error indicating the a backup export could not export the user's data.")];
            return;
        }

        if (self.isComplete) {
            return;
        }
        [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_EXPORT",
                                                @"Indicates that the backup export data is being exported.")
                                   progress:nil];
        [self exportDatabase:^(BOOL exportDatabaseSuccess) {
            if (!exportDatabaseSuccess) {
                [self failWithErrorDescription:
                          NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                              @"Error indicating the a backup export could not export the user's data.")];
                return;
            }

            if (self.isComplete) {
                return;
            }
            [self saveToCloud:^(NSError *_Nullable saveError) {
                if (saveError) {
                    [weakSelf failWithError:saveError];
                    return;
                }
                [self cleanUpCloud:^(NSError *_Nullable cleanUpError) {
                    if (cleanUpError) {
                        [weakSelf failWithError:cleanUpError];
                        return;
                    }
                    [weakSelf succeed];
                }];
            }];
        }];
    }];
}

- (void)configureExport:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![self ensureJobTempDir]) {
        OWSProdLogAndFail(@"%@ Could not create jobTempDirPath.", self.logTag);
        return completion(NO);
    }

    // We need to verify that we have a valid account.
    // Otherwise, if we re-register on another device, we
    // continue to backup on our old device, overwriting
    // backups from the new device.
    //
    // We use an arbitrary request that requires authentication
    // to verify our account state.
    TSRequest *currentSignedPreKey = [OWSRequestFactory currentSignedPreKeyRequest];
    [[TSNetworkManager sharedManager] makeRequest:currentSignedPreKey
        success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(YES);
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            // TODO: We may want to surface this in the UI.
            DDLogError(@"%@ could not verify account status: %@.", self.logTag, error);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO);
            });
        }];
}

- (void)exportDatabase:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![OWSBackupJob generateRandomDatabaseKeySpecWithKeychainKey:kOWSBackup_ExportDatabaseKeySpec]) {
        OWSProdLogAndFail(@"%@ Could not generate database key spec for export.", self.logTag);
        return completion(NO);
    }

    // TODO: Move this work into the "export database" method.
    NSString *jobDatabaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"database"];
    if (![OWSFileSystem ensureDirectoryExists:jobDatabaseDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create jobDatabaseDirPath.", self.logTag);
        return completion(NO);
    }

    BackupStorageKeySpecBlock keySpecBlock = ^{
        NSData *_Nullable databaseKeySpec =
            [OWSBackupJob loadDatabaseKeySpecWithKeychainKey:kOWSBackup_ExportDatabaseKeySpec];
        if (!databaseKeySpec) {
            OWSProdLogAndFail(@"%@ Could not load database keyspec for export.", self.logTag);
        }
        return databaseKeySpec;
    };

    OWSStorageReference *storageReference = [OWSStorageReference new];
    storageReference.storage =
        [[OWSBackupStorage alloc] initBackupStorageWithDatabaseDirPath:jobDatabaseDirPath keySpecBlock:keySpecBlock];
    if (!storageReference.storage) {
        OWSProdLogAndFail(@"%@ Could not create backupStorage.", self.logTag);
        return completion(NO);
    }

    // TODO: Do we really need to run these registrations on the main thread?
    __weak OWSBackupExportJob *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [storageReference.storage runSyncRegistrations];
        [storageReference.storage runAsyncRegistrationsWithCompletion:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf exportDatabaseContentsAndCleanup:storageReference completion:completion];
            });
        }];
    });
}

- (void)exportDatabaseContentsAndCleanup:(OWSStorageReference *)storageReference
                              completion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(storageReference);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    __weak YapDatabase *_Nullable weakDatabase = nil;
    dispatch_queue_t snapshotQueue;
    dispatch_queue_t writeQueue;
    NSArray<NSString *> *_Nullable allDatabaseFilePaths = nil;

    @autoreleasepool {
        allDatabaseFilePaths = [self exportDatabaseContents:storageReference];
        if (!allDatabaseFilePaths) {
            completion(NO);
        }

        // After the data has been written to the database snapshot,
        // we need to synchronously block until the database has been
        // completely closed.  This is non-trivial because the database
        // does a bunch of async work as its closing.
        YapDatabase *database = storageReference.storage.database;

        weakDatabase = database;
        snapshotQueue = database->snapshotQueue;
        writeQueue = database->writeQueue;

        [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_DATABASE_FINALIZED",
                                                @"Indicates that the backup export data is being finalized.")
                                   progress:nil];

        // Flush these two queues immediately.
        [database flushInternalQueue];
        [database flushCheckpointQueue];

        // Close the database.
        storageReference.storage = nil;
    }

    // Flush these queues, which may contain lingering
    // references to the database.
    dispatch_sync(snapshotQueue,
        ^{
        });
    dispatch_sync(writeQueue,
        ^{
        });

    // YapDatabase retains the registration connection for N seconds.
    // The conneciton retains a strong reference to the database.
    // We therefore need to wait a bit longer to ensure that this
    // doesn't block deallocation.
    NSTimeInterval kRegistrationConnectionDelaySeconds = 5.0 * 1.2;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRegistrationConnectionDelaySeconds * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            // Dispatch to main thread to wait for any lingering notifications fired by
            // database (e.g. cross process notifier).
            dispatch_async(dispatch_get_main_queue(), ^{
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    // Verify that the database is indeed closed.
                    YapDatabase *_Nullable strongDatabase = weakDatabase;
                    OWSAssert(!strongDatabase);

                    // Capture the list of database files to save.
                    NSMutableArray<NSString *> *databaseFilePaths = [NSMutableArray new];
                    for (NSString *filePath in allDatabaseFilePaths) {
                        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                            [databaseFilePaths addObject:filePath];
                        }
                    }
                    if (databaseFilePaths.count < 1) {
                        OWSProdLogAndFail(@"%@ Can't find database file.", self.logTag);
                        return completion(NO);
                    }
                    self.databaseFilePaths = [databaseFilePaths mutableCopy];

                    completion(YES);
                });
            });
        });
}

- (nullable NSArray<NSString *> *)exportDatabaseContents:(OWSStorageReference *)storageReference
{
    OWSAssert(storageReference);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_DATABASE_EXPORT",
                                            @"Indicates that the database data is being exported.")
                               progress:nil];

    YapDatabaseConnection *_Nullable tempDBConnection = storageReference.storage.newDatabaseConnection;
    if (!tempDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create tempDBConnection.", self.logTag);
        return nil;
    }
    YapDatabaseConnection *_Nullable primaryDBConnection = self.primaryStorage.newDatabaseConnection;
    if (!primaryDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create primaryDBConnection.", self.logTag);
        return nil;
    }

    NSString *const kDatabaseSnapshotFilename_Threads = @"threads";
    NSString *const kDatabaseSnapshotFilename_Interactions = @"interactions";
    NSString *const kDatabaseSnapshotFilename_Attachments = @"attachments";
    NSString *const kDatabaseSnapshotFilename_Migrations = @"migrations";
    OWSExportStream *_Nullable exportStream_Threads =
        [OWSExportStream exportStreamWithName:kDatabaseSnapshotFilename_Threads jobTempDirPath:self.jobTempDirPath];
    OWSExportStream *_Nullable exportStream_Interactions =
        [OWSExportStream exportStreamWithName:kDatabaseSnapshotFilename_Interactions
                               jobTempDirPath:self.jobTempDirPath];
    OWSExportStream *_Nullable exportStream_Attachments =
        [OWSExportStream exportStreamWithName:kDatabaseSnapshotFilename_Attachments jobTempDirPath:self.jobTempDirPath];
    OWSExportStream *_Nullable exportStream_Migrations =
        [OWSExportStream exportStreamWithName:kDatabaseSnapshotFilename_Migrations jobTempDirPath:self.jobTempDirPath];
    if (!(exportStream_Threads && exportStream_Interactions && exportStream_Attachments && exportStream_Migrations)) {
        return nil;
    }
    NSArray<OWSExportStream *> *exportStreams = @[
        exportStream_Threads,
        exportStream_Interactions,
        exportStream_Attachments,
        exportStream_Migrations,
    ];

    __block unsigned long long copiedThreads = 0;
    __block unsigned long long copiedInteractions = 0;
    __block unsigned long long copiedEntities = 0;
    __block unsigned long long copiedAttachments = 0;
    __block unsigned long long copiedMigrations = 0;

    self.attachmentFilePathMap = [NSMutableDictionary new];

    __block BOOL aborted = NO;
    [primaryDBConnection readWithBlock:^(YapDatabaseReadTransaction *srcTransaction) {
        [tempDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *dstTransaction) {
            [dstTransaction setObject:@(YES)
                               forKey:kOWSBackup_Snapshot_ValidKey
                         inCollection:kOWSBackup_Snapshot_Collection];

            // Copy threads.
            [srcTransaction
                enumerateKeysAndObjectsInCollection:[TSThread collection]
                                         usingBlock:^(NSString *key, id object, BOOL *stop) {
                                             if (self.isComplete) {
                                                 *stop = YES;
                                                 return;
                                             }
                                             if (![object isKindOfClass:[TSThread class]]) {
                                                 OWSProdLogAndFail(
                                                     @"%@ unexpected class: %@", self.logTag, [object class]);
                                                 return;
                                             }
                                             TSThread *thread = object;
                                             [thread saveWithTransaction:dstTransaction];
                                             copiedThreads++;
                                             copiedEntities++;

                                             if (![exportStream_Threads writeObject:thread]) {
                                                 *stop = YES;
                                                 aborted = YES;
                                                 return;
                                             }
                                         }];

            // Copy attachments.
            [srcTransaction
                enumerateKeysAndObjectsInCollection:[TSAttachment collection]
                                         usingBlock:^(NSString *key, id object, BOOL *stop) {
                                             if (self.isComplete) {
                                                 *stop = YES;
                                                 return;
                                             }
                                             if (![object isKindOfClass:[TSAttachment class]]) {
                                                 OWSProdLogAndFail(
                                                     @"%@ unexpected class: %@", self.logTag, [object class]);
                                                 return;
                                             }
                                             if ([object isKindOfClass:[TSAttachmentStream class]]) {
                                                 TSAttachmentStream *attachmentStream = object;
                                                 NSString *_Nullable filePath = attachmentStream.filePath;
                                                 if (filePath) {
                                                     OWSAssert(attachmentStream.uniqueId.length > 0);
                                                     self.attachmentFilePathMap[attachmentStream.uniqueId] = filePath;
                                                 }
                                             }
                                             TSAttachment *attachment = object;
                                             [attachment saveWithTransaction:dstTransaction];
                                             copiedAttachments++;
                                             copiedEntities++;

                                             if (![exportStream_Attachments writeObject:attachment]) {
                                                 *stop = YES;
                                                 aborted = YES;
                                                 return;
                                             }
                                         }];

            // Copy interactions.
            //
            // Interactions refer to threads and attachments, so copy the last.
            [srcTransaction
                enumerateKeysAndObjectsInCollection:[TSInteraction collection]
                                         usingBlock:^(NSString *key, id object, BOOL *stop) {
                                             if (self.isComplete) {
                                                 *stop = YES;
                                                 return;
                                             }
                                             if (![object isKindOfClass:[TSInteraction class]]) {
                                                 OWSProdLogAndFail(
                                                     @"%@ unexpected class: %@", self.logTag, [object class]);
                                                 return;
                                             }
                                             // Ignore disappearing messages.
                                             if ([object isKindOfClass:[TSMessage class]]) {
                                                 TSMessage *message = object;
                                                 if (message.isExpiringMessage) {
                                                     return;
                                                 }
                                             }
                                             TSInteraction *interaction = object;
                                             // Ignore dynamic interactions.
                                             if (interaction.isDynamicInteraction) {
                                                 return;
                                             }
                                             [interaction saveWithTransaction:dstTransaction];
                                             copiedInteractions++;
                                             copiedEntities++;

                                             if (![exportStream_Interactions writeObject:interaction]) {
                                                 *stop = YES;
                                                 aborted = YES;
                                                 return;
                                             }
                                         }];

            // Copy migrations.
            [srcTransaction
                enumerateKeysAndObjectsInCollection:[OWSDatabaseMigration collection]
                                         usingBlock:^(NSString *key, id object, BOOL *stop) {
                                             if (self.isComplete) {
                                                 *stop = YES;
                                                 return;
                                             }
                                             if (![object isKindOfClass:[OWSDatabaseMigration class]]) {
                                                 OWSProdLogAndFail(
                                                     @"%@ unexpected class: %@", self.logTag, [object class]);
                                                 return;
                                             }
                                             OWSDatabaseMigration *migration = object;
                                             [migration saveWithTransaction:dstTransaction];
                                             copiedMigrations++;
                                             copiedEntities++;

                                             if (![exportStream_Migrations writeObject:migration]) {
                                                 *stop = YES;
                                                 aborted = YES;
                                                 return;
                                             }
                                         }];
        }];
    }];

    unsigned long long totalZipFileSize = 0;
    for (OWSExportStream *exportStream in exportStreams) {
        if (![exportStream closeAndZipData]) {
            DDLogError(@"%@ couldn't close database snapshot zip.", self.logTag);
            return nil;
        }
        NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:exportStream.zipFilePath];
        if (!fileSize) {
            DDLogError(@"%@ couldn't get file size of database snapshot zip.", self.logTag);
            return nil;
        }
        totalZipFileSize += fileSize.unsignedLongLongValue;
    }

    if (aborted) {
        return nil;
    }

    if (self.isComplete) {
        return nil;
    }
    // TODO: Should we do a database checkpoint?

    DDLogInfo(@"%@ copiedThreads: %llu", self.logTag, copiedThreads);
    DDLogInfo(@"%@ copiedMessages: %llu", self.logTag, copiedInteractions);
    DDLogInfo(@"%@ copiedEntities: %llu", self.logTag, copiedEntities);
    DDLogInfo(@"%@ copiedAttachments: %llu", self.logTag, copiedAttachments);
    DDLogInfo(@"%@ copiedMigrations: %llu", self.logTag, copiedMigrations);

    [storageReference.storage logFileSizes];

    unsigned long long totalDbFileSize
        = ([OWSFileSystem fileSizeOfPath:storageReference.storage.databaseFilePath].unsignedLongLongValue +
            [OWSFileSystem fileSizeOfPath:storageReference.storage.databaseFilePath_WAL].unsignedLongLongValue +
            [OWSFileSystem fileSizeOfPath:storageReference.storage.databaseFilePath_SHM].unsignedLongLongValue);
    if (totalZipFileSize > 0 && totalDbFileSize > 0) {
        DDLogInfo(@"%@ file size savings: %llu / %llu = %0.2f",
            self.logTag,
            totalZipFileSize,
            totalDbFileSize,
            totalZipFileSize / (CGFloat)totalDbFileSize);
    }

    // Capture the list of files to save.
    return @[
        storageReference.storage.databaseFilePath,
        storageReference.storage.databaseFilePath_WAL,
        storageReference.storage.databaseFilePath_SHM,
    ];
}

- (BOOL)writeObject:(TSYapDatabaseObject *)object fileHandle:(NSFileHandle *)fileHandle
{
    OWSAssert(object);
    OWSAssert(fileHandle);

    NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:object];
    if (!data) {
        OWSProdLogAndFail(@"%@ couldn't serialize database object: %@", self.logTag, [object class]);
        return NO;
    }

    // We use a fixed width data type.
    unsigned int dataLength = (unsigned int)data.length;
    NSData *dataLengthData = [NSData dataWithBytes:&dataLength length:sizeof(dataLength)];
    [fileHandle writeData:dataLengthData];
    [fileHandle writeData:data];
    return YES;
}

- (void)saveToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.databaseRecordMap = [NSMutableDictionary new];
    self.attachmentRecordMap = [NSMutableDictionary new];

    [self saveNextFileToCloud:completion];
}

// This method uploads one file (the "next" file) each time it
// is called.  Each successful file upload re-invokes this method
// until the last (the manifest file).
- (void)saveNextFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    if (self.isComplete) {
        return;
    }

    CGFloat progress
        = (self.databaseRecordMap.count / (CGFloat)(self.databaseRecordMap.count + self.databaseFilePaths.count));
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_UPLOAD",
                                            @"Indicates that the backup export data is being uploaded.")
                               progress:@(progress)];

    if ([self saveNextDatabaseFileToCloud:completion]) {
        return;
    }
    if ([self saveNextAttachmentFileToCloud:completion]) {
        return;
    }
    [self saveManifestFileToCloud:completion];
}

- (BOOL)saveNextDatabaseFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.databaseFilePaths.count < 1) {
        return NO;
    }

    NSString *filePath = self.databaseFilePaths.lastObject;
    [self.databaseFilePaths removeLastObject];
    // Database files are encrypted and can be safely stored unencrypted in the cloud.
    // TODO: Security review.
    [OWSBackupAPI saveEphemeralDatabaseFileToCloudWithFileUrl:[NSURL fileURLWithPath:filePath]
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSBackupExportJob *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                strongSelf.databaseRecordMap[recordName] = [filePath lastPathComponent];
                [strongSelf saveNextFileToCloud:completion];
            });
        }
        failure:^(NSError *error) {
            // Database files are critical so any error uploading them is unrecoverable.
            DDLogVerbose(@"%@ error while saving file: %@", self.logTag, filePath);
            completion(error);
        }];
    return YES;
}

- (BOOL)saveNextAttachmentFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.attachmentFilePathMap.count < 1) {
        return NO;
    }

    NSString *attachmentId = self.attachmentFilePathMap.allKeys.lastObject;
    NSString *attachmentFilePath = self.attachmentFilePathMap[attachmentId];
    [self.attachmentFilePathMap removeObjectForKey:attachmentId];

    // OWSAttachmentExport is used to lazily write an encrypted copy of the
    // attachment to disk.
    OWSAttachmentExport *attachmentExport = [OWSAttachmentExport new];
    attachmentExport.delegate = self.delegate;
    attachmentExport.jobTempDirPath = self.jobTempDirPath;
    attachmentExport.attachmentId = attachmentId;
    attachmentExport.attachmentFilePath = attachmentFilePath;

    [OWSBackupAPI savePersistentFileOnceToCloudWithFileId:attachmentId
        fileUrlBlock:^{
            [attachmentExport prepareForUpload];
            if (attachmentExport.tempFilePath.length < 1) {
                DDLogError(@"%@ attachment export missing temp file path", self.logTag);
                return (NSURL *)nil;
            }
            if (attachmentExport.relativeFilePath.length < 1) {
                DDLogError(@"%@ attachment export missing relative file path", self.logTag);
                return (NSURL *)nil;
            }
            return [NSURL fileURLWithPath:attachmentExport.tempFilePath];
        }
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSBackupExportJob *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                strongSelf.attachmentRecordMap[recordName] = attachmentExport.relativeFilePath;
                DDLogVerbose(@"%@ exported attachment: %@ as %@",
                    self.logTag,
                    attachmentFilePath,
                    attachmentExport.relativeFilePath);
                [strongSelf saveNextFileToCloud:completion];
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Attachment files are non-critical so any error uploading them is recoverable.
                [weakSelf saveNextFileToCloud:completion];
            });
        }];
    return YES;
}

- (void)saveManifestFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    if (![self writeManifestFile]) {
        completion(OWSErrorWithCodeDescription(OWSErrorCodeExportBackupFailed,
            NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                @"Error indicating the a backup export could not export the user's data.")));
        return;
    }
    OWSAssert(self.manifestFilePath);

    __weak OWSBackupExportJob *weakSelf = self;

    [OWSBackupAPI upsertManifestFileToCloudWithFileUrl:[NSURL fileURLWithPath:self.manifestFilePath]
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSBackupExportJob *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                strongSelf.manifestRecordName = recordName;

                // All files have been saved to the cloud.
                completion(nil);
            });
        }
        failure:^(NSError *error) {
            // The manifest file is critical so any error uploading them is unrecoverable.
            completion(error);
        }];
}

- (BOOL)writeManifestFile
{
    OWSAssert(self.databaseRecordMap.count > 0);
    OWSAssert(self.attachmentRecordMap);
    OWSAssert(self.jobTempDirPath.length > 0);

    NSData *_Nullable databaseKeySpec =
        [OWSBackupJob loadDatabaseKeySpecWithKeychainKey:kOWSBackup_ExportDatabaseKeySpec];
    if (databaseKeySpec.length < 1) {
        OWSProdLogAndFail(@"%@ Could not load database keyspec for export.", self.logTag);
        return nil;
    }

    NSDictionary *json = @{
        kOWSBackup_ManifestKey_DatabaseFiles : self.databaseRecordMap,
        kOWSBackup_ManifestKey_AttachmentFiles : self.attachmentRecordMap,
        // JSON doesn't support byte arrays.
        kOWSBackup_ManifestKey_DatabaseKeySpec : databaseKeySpec.base64EncodedString,
    };

    DDLogVerbose(@"%@ json: %@", self.logTag, json);

    NSError *error;
    NSData *_Nullable jsonData =
        [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        OWSProdLogAndFail(@"%@ error encoding manifest file: %@", self.logTag, error);
        return NO;
    }
    self.manifestFilePath =
        [OWSBackupJob encryptDataAsTempFile:jsonData jobTempDirPath:self.jobTempDirPath delegate:self.delegate];
    return self.manifestFilePath != nil;
}

- (void)cleanUpCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CLEAN_UP",
                                            @"Indicates that the cloud is being cleaned up.")
                               progress:nil];

    // Now that our backup export has successfully completed,
    // we try to clean up the cloud.  We can safely delete any
    // records not involved in this backup export.
    NSMutableSet<NSString *> *activeRecordNames = [NSMutableSet new];

    OWSAssert(self.databaseRecordMap.count > 0);
    [activeRecordNames addObjectsFromArray:self.databaseRecordMap.allKeys];

    OWSAssert(self.attachmentRecordMap);
    [activeRecordNames addObjectsFromArray:self.attachmentRecordMap.allKeys];

    OWSAssert(self.manifestRecordName.length > 0);
    [activeRecordNames addObject:self.manifestRecordName];

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
        // Ensure that we continue to work off the main thread.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
            [obsoleteRecordNames addObjectsFromArray:recordNames];
            [obsoleteRecordNames minusSet:activeRecordNames];

            DDLogVerbose(@"%@ recordNames: %zd - activeRecordNames: %zd = obsoleteRecordNames: %zd",
                self.logTag,
                recordNames.count,
                activeRecordNames.count,
                obsoleteRecordNames.count);

            [weakSelf deleteRecordsFromCloud:[obsoleteRecordNames.allObjects mutableCopy]
                                deletedCount:0
                                  completion:completion];
        });
    }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Cloud cleanup is non-critical so any error is recoverable.
                completion(nil);
            });
        }];
}

- (void)deleteRecordsFromCloud:(NSMutableArray<NSString *> *)obsoleteRecordNames
                  deletedCount:(NSUInteger)deletedCount
                    completion:(OWSBackupJobCompletion)completion
{
    OWSAssert(obsoleteRecordNames);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (obsoleteRecordNames.count < 1) {
        // No more records to delete; cleanup is complete.
        completion(nil);
        return;
    }

    CGFloat progress = (obsoleteRecordNames.count / (CGFloat)(obsoleteRecordNames.count + deletedCount));
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CLEAN_UP",
                                            @"Indicates that the cloud is being cleaned up.")
                               progress:@(progress)];

    NSString *recordName = obsoleteRecordNames.lastObject;
    [obsoleteRecordNames removeLastObject];

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI deleteRecordFromCloudWithRecordName:recordName
        success:^{
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
                                    deletedCount:deletedCount + 1
                                      completion:completion];
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Cloud cleanup is non-critical so any error is recoverable.
                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
                                    deletedCount:deletedCount + 1
                                      completion:completion];
            });
        }];
}

@end

NS_ASSUME_NONNULL_END
