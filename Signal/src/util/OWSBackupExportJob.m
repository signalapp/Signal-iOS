//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExportJob.h"
#import "Signal-Swift.h"
#import "zlib.h"
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

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ExportDatabaseKeySpec = @"kOWSBackup_ExportDatabaseKeySpec";

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

@interface OWSBackupExportJob () <SSZipArchiveDelegate>

@property (nonatomic, nullable) OWSBackupStorage *backupStorage;

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
    [self configureExport:^(BOOL success) {
        if (!success) {
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
        if (![self exportDatabase]) {
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
}

- (void)configureExport:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![self ensureJobTempDir]) {
        OWSProdLogAndFail(@"%@ Could not create jobTempDirPath.", self.logTag);
        return completion(NO);
    }

    if (![OWSBackupJob generateRandomDatabaseKeySpecWithKeychainKey:kOWSBackup_ExportDatabaseKeySpec]) {
        OWSProdLogAndFail(@"%@ Could not generate database key spec for export.", self.logTag);
        return completion(NO);
    }

    NSString *exportDatabaseDirPath = [self.jobTempDirPath stringByAppendingPathComponent:@"Database"];

    if (![OWSFileSystem ensureDirectoryExists:exportDatabaseDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create exportDatabaseDirPath.", self.logTag);
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
    self.backupStorage =
        [[OWSBackupStorage alloc] initBackupStorageWithDatabaseDirPath:exportDatabaseDirPath keySpecBlock:keySpecBlock];
    if (!self.backupStorage) {
        OWSProdLogAndFail(@"%@ Could not create backupStorage.", self.logTag);
        return completion(NO);
    }

    // TODO: Do we really need to run these registrations on the main thread?
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.backupStorage runSyncRegistrations];
        [self.backupStorage runAsyncRegistrationsWithCompletion:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(YES);
            });
        }];
    });
}

- (BOOL)exportDatabase
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    YapDatabaseConnection *_Nullable tempDBConnection = self.backupStorage.newDatabaseConnection;
    if (!tempDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create tempDBConnection.", self.logTag);
        return NO;
    }
    YapDatabaseConnection *_Nullable primaryDBConnection = self.primaryStorage.newDatabaseConnection;
    if (!primaryDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create primaryDBConnection.", self.logTag);
        return NO;
    }

    __block unsigned long long copiedThreads = 0;
    __block unsigned long long copiedInteractions = 0;
    __block unsigned long long copiedEntities = 0;
    __block unsigned long long copiedAttachments = 0;

    self.attachmentFilePathMap = [NSMutableDictionary new];

    [primaryDBConnection readWithBlock:^(YapDatabaseReadTransaction *srcTransaction) {
        [tempDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *dstTransaction) {
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

            // Copy interactions.
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
                                         }];
        }];
    }];

    // TODO: Should we do a database checkpoint?

    DDLogInfo(@"%@ copiedThreads: %llu", self.logTag, copiedThreads);
    DDLogInfo(@"%@ copiedMessages: %llu", self.logTag, copiedInteractions);
    DDLogInfo(@"%@ copiedEntities: %llu", self.logTag, copiedEntities);
    DDLogInfo(@"%@ copiedAttachments: %llu", self.logTag, copiedAttachments);

    [self.backupStorage logFileSizes];

    // Capture the list of files to save.
    self.databaseFilePaths = [@[
        self.backupStorage.databaseFilePath,
        self.backupStorage.databaseFilePath_WAL,
        self.backupStorage.databaseFilePath_SHM,
    ] mutableCopy];

    // Close the database.
    tempDBConnection = nil;
    self.backupStorage = nil;

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

    __weak OWSBackupExportJob *weakSelf = self;

    if (self.databaseFilePaths.count > 0) {
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
                completion(error);
            }];
        return;
    }

    if (self.attachmentFilePathMap.count > 0) {
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
        return;
    }

    if (!self.manifestFilePath) {
        if (![self writeManifestFile]) {
            completion(OWSErrorWithCodeDescription(OWSErrorCodeExportBackupFailed,
                NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                    @"Error indicating the a backup export could not export the user's data.")));
            return;
        }
        OWSAssert(self.manifestFilePath);

        [OWSBackupAPI upsertManifestFileToCloudWithFileUrl:[NSURL fileURLWithPath:self.manifestFilePath]
            success:^(NSString *recordName) {
                // Ensure that we continue to work off the main thread.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    OWSBackupExportJob *strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }
                    strongSelf.manifestRecordName = recordName;
                    [strongSelf saveNextFileToCloud:completion];
                });
            }
            failure:^(NSError *error) {
                // The manifest file is critical so any error uploading them is unrecoverable.
                completion(error);
            }];
        return;
    }

    // All files have been saved to the cloud.
    completion(nil);
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
