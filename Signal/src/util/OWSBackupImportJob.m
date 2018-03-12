//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportJob.h"
#import "Signal-Swift.h"
#import "zlib.h"
#import <Curve25519Kit/Randomness.h>
#import <SSZipArchive/SSZipArchive.h>
#import <SignalServiceKit/NSData+Base64.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBackupStorage.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/Threading.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ImportDatabaseKeySpec = @"kOWSBackup_ImportDatabaseKeySpec";

#pragma mark -

@interface OWSBackupImportJob () <SSZipArchiveDelegate>

//@property (nonatomic, nullable) OWSBackupStorage *backupStorage;

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

//@property (nonatomic) NSMutableArray<NSString *> *databaseFilePaths;
// A map of "record name"-to-"file name".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *databaseRecordMap;

//// A map of "attachment id"-to-"local file path".
//@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *attachmentFilePathMap;
// A map of "record name"-to-"file relative path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *attachmentRecordMap;

// A map of "record name"-to-"downloaded file path".
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *downloadedFileMap;

//
//@property (nonatomic, nullable) NSString *manifestFilePath;
//@property (nonatomic, nullable) NSString *manifestRecordName;

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

    __weak OWSBackupImportJob *weakSelf = self;
    [self configureImport:^(BOOL configureSuccess) {
        if (!configureSuccess) {
            [weakSelf failWithErrorDescription:
                          NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
                              @"Error indicating the a backup import could not import the user's data.")];
            return;
        }

        if (weakSelf.isComplete) {
            return;
        }
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
            // TODO:
        }];

        //        [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_IMPORT",
        //                                                @"Indicates that the backup import data is being imported.")
        //                                   progress:nil];
        //        if (![self importDatabase]) {
        //            [self failWithErrorDescription:
        //                      NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
        //                          @"Error indicating the a backup import could not import the user's data.")];
        //            return;
        //        }
        //        if (self.isComplete) {
        //            return;
        //        }
        //        [self saveToCloud:^(NSError *_Nullable saveError) {
        //            if (saveError) {
        //                [weakSelf failWithError:saveError];
        //                return;
        //            }
        //            [self cleanUpCloud:^(NSError *_Nullable cleanUpError) {
        //                if (cleanUpError) {
        //                    [weakSelf failWithError:cleanUpError];
        //                    return;
        //                }
        //                [weakSelf succeed];
        //            }];
        //        }];
    }];
}

// TODO: Convert these methods to sync.
- (void)configureImport:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![self ensureJobTempDir]) {
        OWSProdLogAndFail(@"%@ Could not create jobTempDirPath.", self.logTag);
        return completion(NO);
    }
    completion(YES);

    //    NSString *importDatabaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"Database"];
    //    self.tempDatabaseKeySpec = [Randomness generateRandomBytes:(int)kSQLCipherKeySpecLength];
    //
    //    if (![OWSFileSystem ensureDirectoryExists:importDatabaseDirPath]) {
    //        OWSProdLogAndFail(@"%@ Could not create importDatabaseDirPath.", self.logTag);
    //        return completion(NO);
    //    }
    //    if (!self.tempDatabaseKeySpec) {
    //        OWSProdLogAndFail(@"%@ Could not create tempDatabaseKeySpec.", self.logTag);
    //        return completion(NO);
    //    }
    //    __weak OWSBackupImportJob *weakSelf = self;
    //    BackupStorageKeySpecBlock keySpecBlock = ^{
    //        return weakSelf.tempDatabaseKeySpec;
    //    };
    //    self.backupStorage =
    //        [[OWSBackupStorage alloc] initBackupStorageWithDatabaseDirPath:importDatabaseDirPath
    //        keySpecBlock:keySpecBlock];
    //    if (!self.backupStorage) {
    //        OWSProdLogAndFail(@"%@ Could not create backupStorage.", self.logTag);
    //        return completion(NO);
    //    }
    //
    //    // TODO: Do we really need to run these registrations on the main thread?
    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        [self.backupStorage runSyncRegistrations];
    //        [self.backupStorage runAsyncRegistrationsWithCompletion:^{
    //            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //                completion(YES);
    //            });
    //        }];
    //    });
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

    DDLogVerbose(@"%@ json: %@", self.logTag, json);
    [DDLog flushLog];

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

    DDLogVerbose(@"%@ attachmentRecordMap: %@", self.logTag, attachmentRecordMap);
    [DDLog flushLog];

    self.databaseRecordMap = [databaseRecordMap mutableCopy];
    self.attachmentRecordMap = [attachmentRecordMap mutableCopy];

    return completion(YES);
}

//- (void)downloadDatabaseFiles:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(completion);
//
//    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
//
//    NSString *databaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"Database"];
//    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
//        OWSProdLogAndFail(@"%@ Could not create databaseDirPath.", self.logTag);
//        return completion(OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed,
//                                                      NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
//                                                                        @"Error indicating the a backup import could
//                                                                        not import the user's data.")));
//    }
//
//    //    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
//    NSMutableArray<NSString *> *recordNames = [self.databaseRecordMap.allKeys mutableCopy];
//
//    [self downloadNextFile:recordNames
//                dstDirPath:databaseDirPath
//                completion:completion];
//}
//
//- (void)downloadNextFile:(NSMutableArray<NSString *> *)recordNames
//              dstDirPath:(NSString *)dstDirPath
//              completion:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(recordNames);
//    OWSAssert(completion);
//
//    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
//
//    NSString *databaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"Database"];
//    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
//        OWSProdLogAndFail(@"%@ Could not create databaseDirPath.", self.logTag);
//        return completion(OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed,
//                                                      NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
//                                                                        @"Error indicating the a backup import could
//                                                                        not import the user's data.")));
//    }
//
//    //    NSString *database
//    //    self.jobTempDirPath
//
//    //    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
//    NSMutableArray<NSString *> *recordNamesToDownload = [self.databaseRecordMap.allKeys mutableCopy];
//
//    [self downloadNextFile:recordNamesToDownload
//                completion:completion];
//    __weak OWSBackupImportJob *weakSelf = self;
//    [OWSBackupAPI downloadManifestFromCloudWithSuccess:^(NSData *data) {
//        [weakSelf processManifest:data
//                       completion:^(BOOL success) {
//                           if (success) {
//                               completion(nil);
//                           } else {
//                               completion(OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed,
//                                                                      NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
//                                                                                        @"Error indicating the a
//                                                                                        backup import could not import
//                                                                                        the user's data.")));
//                           }
//                       }];
//    }
//                                               failure:^(NSError *error) {
//                                                   // The manifest file is critical so any error downloading it is
//                                                   unrecoverable. OWSProdLogAndFail(@"%@ Could not download
//                                                   manifest.", self.logTag); completion(error);
//                                               }];
//}

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

    DDLogVerbose(@"%@ self.attachmentRecordMap: %@", self.logTag, self.attachmentRecordMap);
    [DDLog flushLog];

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
    // TODO: Remove
    DDLogVerbose(@"%@ Restored attachment file: %@ -> %@", self.logTag, downloadedFilePath, dstFilePath);

    return YES;
}

//- (void)saveToCloud:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(completion);
//
//    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
//
//    self.databaseRecordMap = [NSMutableDictionary new];
//    self.attachmentRecordMap = [NSMutableDictionary new];
//
//    [self saveNextFileToCloud:completion];
//}
//
//- (void)saveNextFileToCloud:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(completion);
//
//    if (self.isComplete) {
//        return;
//    }
//
//    CGFloat progress
//        = (self.databaseRecordMap.count / (CGFloat)(self.databaseRecordMap.count + self.databaseFilePaths.count));
//    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_UPLOAD",
//                                            @"Indicates that the backup import data is being uploaded.")
//                               progress:@(progress)];
//
//    __weak OWSBackupImportJob *weakSelf = self;
//
//    if (self.databaseFilePaths.count > 0) {
//        NSString *filePath = self.databaseFilePaths.lastObject;
//        [self.databaseFilePaths removeLastObject];
//        // Database files are encrypted and can be safely stored unencrypted in the cloud.
//        // TODO: Security review.
//        [OWSBackupAPI saveEphemeralDatabaseFileToCloudWithFileUrl:[NSURL fileURLWithPath:filePath]
//            success:^(NSString *recordName) {
//                // Ensure that we continue to work off the main thread.
//                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                    OWSBackupImportJob *strongSelf = weakSelf;
//                    if (!strongSelf) {
//                        return;
//                    }
//                    strongSelf.databaseRecordMap[recordName] = [filePath lastPathComponent];
//                    [strongSelf saveNextFileToCloud:completion];
//                });
//            }
//            failure:^(NSError *error) {
//                // Database files are critical so any error uploading them is unrecoverable.
//                completion(error);
//            }];
//        return;
//    }
//
//    if (self.attachmentFilePathMap.count > 0) {
//        NSString *attachmentId = self.attachmentFilePathMap.allKeys.lastObject;
//        NSString *attachmentFilePath = self.attachmentFilePathMap[attachmentId];
//        [self.attachmentFilePathMap removeObjectForKey:attachmentId];
//
//        // OWSAttachmentImport is used to lazily write an encrypted copy of the
//        // attachment to disk.
//        OWSAttachmentImport *attachmentImport = [OWSAttachmentImport new];
//        attachmentImport.delegate = self.delegate;
//        attachmentImport.jobTempDirPath = self.jobTempDirPath;
//        attachmentImport.attachmentId = attachmentId;
//        attachmentImport.attachmentFilePath = attachmentFilePath;
//
//        [OWSBackupAPI savePersistentFileOnceToCloudWithFileId:attachmentId
//            fileUrlBlock:^{
//                [attachmentImport prepareForUpload];
//                if (attachmentImport.tempFilePath.length < 1) {
//                    DDLogError(@"%@ attachment import missing temp file path", self.logTag);
//                    return (NSURL *)nil;
//                }
//                if (attachmentImport.relativeFilePath.length < 1) {
//                    DDLogError(@"%@ attachment import missing relative file path", self.logTag);
//                    return (NSURL *)nil;
//                }
//                return [NSURL fileURLWithPath:attachmentImport.tempFilePath];
//            }
//            success:^(NSString *recordName) {
//                // Ensure that we continue to work off the main thread.
//                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                    OWSBackupImportJob *strongSelf = weakSelf;
//                    if (!strongSelf) {
//                        return;
//                    }
//                    strongSelf.attachmentRecordMap[recordName] = attachmentImport.relativeFilePath;
//                    [strongSelf saveNextFileToCloud:completion];
//                });
//            }
//            failure:^(NSError *error) {
//                // Ensure that we continue to work off the main thread.
//                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                    // Attachment files are non-critical so any error uploading them is recoverable.
//                    [weakSelf saveNextFileToCloud:completion];
//                });
//            }];
//        return;
//    }
//
//    if (!self.manifestFilePath) {
//        if (![self writeManifestFile]) {
//            completion(OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed,
//                NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
//                    @"Error indicating the a backup import could not import the user's data.")));
//            return;
//        }
//        OWSAssert(self.manifestFilePath);
//
//        [OWSBackupAPI upsertManifestFileToCloudWithFileUrl:[NSURL fileURLWithPath:self.manifestFilePath]
//            success:^(NSString *recordName) {
//                // Ensure that we continue to work off the main thread.
//                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                    OWSBackupImportJob *strongSelf = weakSelf;
//                    if (!strongSelf) {
//                        return;
//                    }
//                    strongSelf.manifestRecordName = recordName;
//                    [strongSelf saveNextFileToCloud:completion];
//                });
//            }
//            failure:^(NSError *error) {
//                // The manifest file is critical so any error uploading them is unrecoverable.
//                completion(error);
//            }];
//        return;
//    }
//
//    // All files have been saved to the cloud.
//    completion(nil);
//}
//
//- (BOOL)writeManifestFile
//{
//    OWSAssert(self.databaseRecordMap.count > 0);
//    OWSAssert(self.attachmentRecordMap);
//    OWSAssert(self.jobTempDirPath.length > 0);
//    OWSAssert(self.tempDatabaseKeySpec.length > 0);
//
//    NSDictionary *json = @{
//        @"database_files" : self.databaseRecordMap,
//        @"attachment_files" : self.attachmentRecordMap,
//        // JSON doesn't support byte arrays.
//        @"database_key_spec" : self.tempDatabaseKeySpec.base64EncodedString,
//    };
//    NSError *error;
//    NSData *_Nullable jsonData =
//        [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
//    if (!jsonData || error) {
//        OWSProdLogAndFail(@"%@ error encoding manifest file: %@", self.logTag, error);
//        return NO;
//    }
//    // TODO: Encrypt the manifest.
//    self.manifestFilePath = [self.jobTempDirPath stringByAppendingPathComponent:@"manifest.json"];
//    if (![jsonData writeToFile:self.manifestFilePath atomically:YES]) {
//        OWSProdLogAndFail(@"%@ error writing manifest file: %@", self.logTag, error);
//        return NO;
//    }
//    return YES;
//}
//
//- (void)cleanUpCloud:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(completion);
//
//    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
//
//    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_CLEAN_UP",
//                                            @"Indicates that the cloud is being cleaned up.")
//                               progress:nil];
//
//    // Now that our backup import has successfully completed,
//    // we try to clean up the cloud.  We can safely delete any
//    // records not involved in this backup import.
//    NSMutableSet<NSString *> *activeRecordNames = [NSMutableSet new];
//
//    OWSAssert(self.databaseRecordMap.count > 0);
//    [activeRecordNames addObjectsFromArray:self.databaseRecordMap.allKeys];
//
//    OWSAssert(self.attachmentRecordMap);
//    [activeRecordNames addObjectsFromArray:self.attachmentRecordMap.allKeys];
//
//    OWSAssert(self.manifestRecordName.length > 0);
//    [activeRecordNames addObject:self.manifestRecordName];
//
//    __weak OWSBackupImportJob *weakSelf = self;
//    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
//        // Ensure that we continue to work off the main thread.
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
//            [obsoleteRecordNames addObjectsFromArray:recordNames];
//            [obsoleteRecordNames minusSet:activeRecordNames];
//
//            DDLogVerbose(@"%@ recordNames: %zd - activeRecordNames: %zd = obsoleteRecordNames: %zd",
//                self.logTag,
//                recordNames.count,
//                activeRecordNames.count,
//                obsoleteRecordNames.count);
//
//            [weakSelf deleteRecordsFromCloud:[obsoleteRecordNames.allObjects mutableCopy]
//                                deletedCount:0
//                                  completion:completion];
//        });
//    }
//        failure:^(NSError *error) {
//            // Ensure that we continue to work off the main thread.
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                // Cloud cleanup is non-critical so any error is recoverable.
//                completion(nil);
//            });
//        }];
//}
//
//- (void)deleteRecordsFromCloud:(NSMutableArray<NSString *> *)obsoleteRecordNames
//                  deletedCount:(NSUInteger)deletedCount
//                    completion:(OWSBackupJobCompletion)completion
//{
//    OWSAssert(obsoleteRecordNames);
//    OWSAssert(completion);
//
//    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
//
//    if (obsoleteRecordNames.count < 1) {
//        // No more records to delete; cleanup is complete.
//        completion(nil);
//        return;
//    }
//
//    CGFloat progress = (obsoleteRecordNames.count / (CGFloat)(obsoleteRecordNames.count + deletedCount));
//    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_CLEAN_UP",
//                                            @"Indicates that the cloud is being cleaned up.")
//                               progress:@(progress)];
//
//    NSString *recordName = obsoleteRecordNames.lastObject;
//    [obsoleteRecordNames removeLastObject];
//
//    __weak OWSBackupImportJob *weakSelf = self;
//    [OWSBackupAPI deleteRecordFromCloudWithRecordName:recordName
//        success:^{
//            // Ensure that we continue to work off the main thread.
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
//                                    deletedCount:deletedCount + 1
//                                      completion:completion];
//            });
//        }
//        failure:^(NSError *error) {
//            // Ensure that we continue to work off the main thread.
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                // Cloud cleanup is non-critical so any error is recoverable.
//                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
//                                    deletedCount:deletedCount + 1
//                                      completion:completion];
//            });
//        }];
//}

@end

NS_ASSUME_NONNULL_END
