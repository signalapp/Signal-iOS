//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportJob.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/NSData+Base64.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBackupStorage.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ImportDatabaseKeySpec = @"kOWSBackup_ImportDatabaseKeySpec";

#pragma mark -

@interface OWSBackupImportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

// A map of "record name"-to-"file name".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *databaseRecordMap;

// A map of "record name"-to-"file relative path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *attachmentRecordMap;

// A map of "record name"-to-"downloaded file path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *downloadedFileMap;

@end

#pragma mark -

@implementation OWSBackupImportJob

- (void)startAsync
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self updateProgressWithDescription:nil progress:nil];

    __weak OWSBackupImportJob *weakSelf = self;
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
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_CONFIGURATION",
                                            @"Indicates that the backup import is being configured.")
                               progress:nil];

    if (![self configureImport]) {
        [self failWithErrorDescription:NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
                                           @"Error indicating the a backup import could not import the user's data.")];
        return;
    }

    if (self.isComplete) {
        return;
    }

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_IMPORT",
                                            @"Indicates that the backup import data is being imported.")
                               progress:nil];

    __weak OWSBackupImportJob *weakSelf = self;
    [weakSelf downloadAndProcessManifest:^(NSError *_Nullable manifestError) {
        if (manifestError) {
            [weakSelf failWithError:manifestError];
            return;
        }

        if (weakSelf.isComplete) {
            return;
        }

        NSMutableArray<NSString *> *allRecordNames = [NSMutableArray new];
        [allRecordNames addObjectsFromArray:weakSelf.databaseRecordMap.allKeys];
        // TODO: We could skip attachments that have already been restored
        // by previous "backup import" attempts.
        [allRecordNames addObjectsFromArray:weakSelf.attachmentRecordMap.allKeys];
        [weakSelf
            downloadFilesFromCloud:allRecordNames
                        completion:^(NSError *_Nullable fileDownloadError) {
                            if (fileDownloadError) {
                                [weakSelf failWithError:fileDownloadError];
                                return;
                            }

                            if (weakSelf.isComplete) {
                                return;
                            }

                            [weakSelf restoreAttachmentFiles];

                            if (weakSelf.isComplete) {
                                return;
                            }

                            [weakSelf restoreDatabase:^(BOOL restoreDatabaseSuccess) {
                                if (!restoreDatabaseSuccess) {
                                    [weakSelf failWithErrorDescription:NSLocalizedString(
                                                                           @"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
                                                                           @"Error indicating the a backup import "
                                                                           @"could not import the user's data.")];
                                    return;
                                }

                                if (weakSelf.isComplete) {
                                    return;
                                }

                                [weakSelf succeed];
                            }];
                        }];
    }];
}

- (BOOL)configureImport
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![self ensureJobTempDir]) {
        OWSProdLogAndFail(@"%@ Could not create jobTempDirPath.", self.logTag);
        return NO;
    }
    return YES;
}

- (void)downloadAndProcessManifest:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    __weak OWSBackupImportJob *weakSelf = self;
    [OWSBackupAPI downloadManifestFromCloudWithSuccess:^(NSData *data) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [weakSelf processManifest:data
                           completion:^(BOOL success) {
                               if (success) {
                                   completion(nil);
                               } else {
                                   completion(OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed,
                                       NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
                                           @"Error indicating the a backup import could not import the user's data.")));
                               }
                           }];
        });
    }
        failure:^(NSError *error) {
            // The manifest file is critical so any error downloading it is unrecoverable.
            OWSProdLogAndFail(@"%@ Could not download manifest.", self.logTag);
            completion(error);
        }];
}

- (void)processManifest:(NSData *)manifestData completion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    if (self.isComplete) {
        return;
    }

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSError *error;
    NSDictionary<NSString *, id> *_Nullable json =
        [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OWSProdLogAndFail(@"%@ Could not download manifest.", self.logTag);
        return completion(NO);
    }

    NSDictionary<NSString *, NSString *> *_Nullable databaseRecordMap = json[kOWSBackup_ManifestKey_DatabaseFiles];
    NSDictionary<NSString *, NSString *> *_Nullable attachmentRecordMap = json[kOWSBackup_ManifestKey_AttachmentFiles];
    NSString *_Nullable databaseKeySpecBase64 = json[kOWSBackup_ManifestKey_DatabaseKeySpec];
    if (!([databaseRecordMap isKindOfClass:[NSDictionary class]] &&
            [attachmentRecordMap isKindOfClass:[NSDictionary class]] &&
            [databaseKeySpecBase64 isKindOfClass:[NSString class]])) {
        OWSProdLogAndFail(@"%@ Invalid manifest.", self.logTag);
        return completion(NO);
    }
    NSData *_Nullable databaseKeySpec = [NSData dataFromBase64String:databaseKeySpecBase64];
    if (!databaseKeySpec) {
        OWSProdLogAndFail(@"%@ Invalid manifest databaseKeySpec.", self.logTag);
        return completion(NO);
    }
    if (![OWSBackupJob storeDatabaseKeySpec:databaseKeySpec keychainKey:kOWSBackup_ImportDatabaseKeySpec]) {
        OWSProdLogAndFail(@"%@ Couldn't store databaseKeySpec from manifest.", self.logTag);
        return completion(NO);
    }

    self.databaseRecordMap = [databaseRecordMap mutableCopy];
    self.attachmentRecordMap = [attachmentRecordMap mutableCopy];

    return completion(YES);
}

- (void)downloadFilesFromCloud:(NSMutableArray<NSString *> *)recordNames completion:(OWSBackupJobCompletion)completion
{
    OWSAssert(recordNames.count > 0);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // A map of "record name"-to-"downloaded file path".
    self.downloadedFileMap = [NSMutableDictionary new];

    [self downloadNextFileFromCloud:recordNames completion:completion];
}

- (void)downloadNextFileFromCloud:(NSMutableArray<NSString *> *)recordNames
                       completion:(OWSBackupJobCompletion)completion
{
    OWSAssert(recordNames);
    OWSAssert(completion);

    if (self.isComplete) {
        // Job was aborted.
        return completion(nil);
    }

    if (recordNames.count < 1) {
        // All downloads are complete; exit.
        return completion(nil);
    }
    NSString *recordName = recordNames.lastObject;
    [recordNames removeLastObject];

    if (![recordName isKindOfClass:[NSString class]]) {
        DDLogError(@"%@ invalid record name in manifest: %@", self.logTag, [recordName class]);
        // Invalid record name in the manifest. This may be recoverable.
        // Ignore this for now and proceed with the other downloads.
        return [self downloadNextFileFromCloud:recordNames completion:completion];
    }

    // Use a predictable file path so that multiple "import backup" attempts
    // will leverage successful file downloads from previous attempts.
    NSString *tempFilePath = [self.jobTempDirPath stringByAppendingPathComponent:recordName];

    // Skip redundant file download.
    if ([NSFileManager.defaultManager fileExistsAtPath:tempFilePath]) {
        [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];
        self.downloadedFileMap[recordName] = tempFilePath;
        [self downloadNextFileFromCloud:recordNames completion:completion];
        return;
    }

    [OWSBackupAPI downloadFileFromCloudWithRecordName:recordName
        toFileUrl:[NSURL fileURLWithPath:tempFilePath]
        success:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];
                self.downloadedFileMap[recordName] = tempFilePath;
                [self downloadNextFileFromCloud:recordNames completion:completion];
            });
        }
        failure:^(NSError *error) {
            completion(error);
        }];
}

- (void)restoreAttachmentFiles
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSString *attachmentsDirPath = [TSAttachmentStream attachmentsFolder];

    for (NSString *recordName in self.attachmentRecordMap) {
        if (self.isComplete) {
            return;
        }

        NSString *dstRelativePath = self.attachmentRecordMap[recordName];
        if (!
            [self restoreFileWithRecordName:recordName dstRelativePath:dstRelativePath dstDirPath:attachmentsDirPath]) {
            // Attachment-related errors are recoverable and can be ignored.
            continue;
        }
    }
}

- (void)restoreDatabase:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSString *jobDatabaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"database"];
    if (![OWSFileSystem ensureDirectoryExists:jobDatabaseDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create jobDatabaseDirPath.", self.logTag);
        return completion(NO);
    }

    for (NSString *recordName in self.databaseRecordMap) {
        if (self.isComplete) {
            return completion(NO);
        }

        NSString *dstRelativePath = self.databaseRecordMap[recordName];
        if (!
            [self restoreFileWithRecordName:recordName dstRelativePath:dstRelativePath dstDirPath:jobDatabaseDirPath]) {
            // Database-related errors are unrecoverable.
            return completion(NO);
        }
    }

    BackupStorageKeySpecBlock keySpecBlock = ^{
        NSData *_Nullable databaseKeySpec =
            [OWSBackupJob loadDatabaseKeySpecWithKeychainKey:kOWSBackup_ImportDatabaseKeySpec];
        if (!databaseKeySpec) {
            OWSProdLogAndFail(@"%@ Could not load database keyspec for import.", self.logTag);
        }
        return databaseKeySpec;
    };
    OWSBackupStorage *_Nullable backupStorage =
        [[OWSBackupStorage alloc] initBackupStorageWithDatabaseDirPath:jobDatabaseDirPath keySpecBlock:keySpecBlock];
    if (!backupStorage) {
        OWSProdLogAndFail(@"%@ Could not create backupStorage.", self.logTag);
        return completion(NO);
    }

    // TODO: Do we really need to run these registrations on the main thread?
    __weak OWSBackupImportJob *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [backupStorage runSyncRegistrations];
        [backupStorage runAsyncRegistrationsWithCompletion:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf restoreDatabaseContents:backupStorage completion:completion];
                completion(YES);
            });
        }];
    });
}

- (void)restoreDatabaseContents:(OWSBackupStorage *)backupStorage completion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(backupStorage);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (self.isComplete) {
        return completion(NO);
    }

    YapDatabaseConnection *_Nullable tempDBConnection = backupStorage.newDatabaseConnection;
    if (!tempDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create tempDBConnection.", self.logTag);
        return completion(NO);
    }
    YapDatabaseConnection *_Nullable primaryDBConnection = self.primaryStorage.newDatabaseConnection;
    if (!primaryDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create primaryDBConnection.", self.logTag);
        return completion(NO);
    }

    __block unsigned long long copiedThreads = 0;
    __block unsigned long long copiedInteractions = 0;
    __block unsigned long long copiedEntities = 0;
    __block unsigned long long copiedAttachments = 0;

    [tempDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *srcTransaction) {
        [primaryDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *dstTransaction) {
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
                                         }];

            // Copy attachments.
            [srcTransaction
                enumerateKeysAndObjectsInCollection:[TSAttachmentStream collection]
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
                                             TSAttachment *attachment = object;
                                             [attachment saveWithTransaction:dstTransaction];
                                             copiedAttachments++;
                                             copiedEntities++;
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
                                         }];
        }];
    }];

    DDLogInfo(@"%@ copiedThreads: %llu", self.logTag, copiedThreads);
    DDLogInfo(@"%@ copiedMessages: %llu", self.logTag, copiedInteractions);
    DDLogInfo(@"%@ copiedEntities: %llu", self.logTag, copiedEntities);
    DDLogInfo(@"%@ copiedAttachments: %llu", self.logTag, copiedAttachments);

    [backupStorage logFileSizes];

    // Close the database.
    tempDBConnection = nil;
    backupStorage = nil;

    return completion(YES);
}

- (BOOL)restoreFileWithRecordName:(NSString *)recordName
                  dstRelativePath:(NSString *)dstRelativePath
                       dstDirPath:(NSString *)dstDirPath
{
    OWSAssert(recordName);
    OWSAssert(dstDirPath.length > 0);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![recordName isKindOfClass:[NSString class]]) {
        DDLogError(@"%@ invalid record name in manifest: %@", self.logTag, [recordName class]);
        return NO;
    }
    if (![dstRelativePath isKindOfClass:[NSString class]]) {
        DDLogError(@"%@ invalid dstRelativePath in manifest: %@", self.logTag, [recordName class]);
        return NO;
    }
    NSString *dstFilePath = [dstDirPath stringByAppendingPathComponent:dstRelativePath];
    if ([NSFileManager.defaultManager fileExistsAtPath:dstFilePath]) {
        DDLogError(@"%@ skipping redundant file restore.", self.logTag);
        return NO;
    }
    NSString *downloadedFilePath = self.downloadedFileMap[recordName];
    if (![NSFileManager.defaultManager fileExistsAtPath:downloadedFilePath]) {
        DDLogError(@"%@ missing downloaded attachment file.", self.logTag);
        return NO;
    }
    NSError *error;
    BOOL success = [NSFileManager.defaultManager moveItemAtPath:downloadedFilePath toPath:dstFilePath error:&error];
    if (!success || error) {
        DDLogError(@"%@ could not restore attachment file.", self.logTag);
        return NO;
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
