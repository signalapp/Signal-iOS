//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportJob.h"
#import "OWSDatabaseMigration.h"
#import "OWSDatabaseMigrationRunner.h"
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

                                [weakSelf ensureMigrations:^(BOOL ensureMigrationsSuccess) {
                                    if (!ensureMigrationsSuccess) {
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

    DDLogVerbose(@"%@ json: %@", self.logTag, json);

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
    DDLogVerbose(@"%@ %s: %zd", self.logTag, __PRETTY_FUNCTION__, self.attachmentRecordMap.count);

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

    NSDictionary<NSString *, Class> *collectionTypeMap = @{
        [TSThread collection] : [TSThread class],
        [TSAttachment collection] : [TSAttachment class],
        [TSInteraction collection] : [TSInteraction class],
        [OWSDatabaseMigration collection] : [OWSDatabaseMigration class],
    };
    // Order matters here.
    NSArray<NSString *> *collectionsToRestore = @[
        [TSThread collection],
        [TSAttachment collection],
        // Interactions refer to threads and attachments,
        // so copy them afterward.
        [TSInteraction collection],
        [OWSDatabaseMigration collection],
    ];
    NSMutableDictionary<NSString *, NSNumber *> *restoredEntityCounts = [NSMutableDictionary new];
    __block unsigned long long copiedEntities = 0;
    __block BOOL aborted = NO;
    [tempDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *srcTransaction) {
        [primaryDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *dstTransaction) {
            for (NSString *collection in collectionsToRestore) {
                if ([collection isEqualToString:[OWSDatabaseMigration collection]]) {
                    // It's okay if there are existing migrations; we'll clear those
                    // before restoring.
                    continue;
                }
                if ([dstTransaction numberOfKeysInCollection:collection] > 0) {
                    DDLogError(@"%@ cannot restore into non-empty database (%@).", self.logTag, collection);
                    aborted = YES;
                    return completion(NO);
                }
            }

            // Clear existing migrations.
            //
            // This is safe since we only ever import into an empty database.
            // Non-database migrations should be idempotent.
            [dstTransaction removeAllObjectsInCollection:[OWSDatabaseMigration collection]];

            // Copy database entities.
            for (NSString *collection in collectionsToRestore) {
                [srcTransaction enumerateKeysAndObjectsInCollection:collection
                                                         usingBlock:^(NSString *key, id object, BOOL *stop) {
                                                             if (self.isComplete) {
                                                                 *stop = YES;
                                                                 aborted = YES;
                                                                 return;
                                                             }
                                                             Class expectedType = collectionTypeMap[collection];
                                                             OWSAssert(expectedType);
                                                             if (![object isKindOfClass:expectedType]) {
                                                                 OWSProdLogAndFail(@"%@ unexpected class: %@ != %@",
                                                                     self.logTag,
                                                                     [object class],
                                                                     expectedType);
                                                                 return;
                                                             }
                                                             TSYapDatabaseObject *databaseObject = object;
                                                             [databaseObject saveWithTransaction:dstTransaction];

                                                             NSUInteger count
                                                                 = restoredEntityCounts[collection].unsignedIntValue;
                                                             restoredEntityCounts[collection] = @(count + 1);
                                                             copiedEntities++;
                                                         }];
            }
        }];
    }];

    if (aborted) {
        return;
    }

    for (NSString *collection in collectionsToRestore) {
        Class expectedType = collectionTypeMap[collection];
        OWSAssert(expectedType);
        DDLogInfo(@"%@ copied %@ (%@): %@", self.logTag, expectedType, collection, restoredEntityCounts[collection]);
    }
    DDLogInfo(@"%@ copiedEntities: %llu", self.logTag, copiedEntities);

    [backupStorage logFileSizes];

    // Close the database.
    tempDBConnection = nil;
    backupStorage = nil;

    return completion(YES);
}

- (void)ensureMigrations:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // It's okay that we do this in a separate transaction from the
    // restoration of backup contents.  If some of migrations don't
    // complete, they'll be run the next time the app launches.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[OWSDatabaseMigrationRunner alloc] initWithPrimaryStorage:self.primaryStorage]
            runAllOutstandingWithCompletion:^{
                completion(YES);
            }];
    });
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
        DDLogError(@"%@ skipping redundant file restore: %@.", self.logTag, dstFilePath);
        return YES;
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

    DDLogError(@"%@ restored file: %@ (%@).", self.logTag, dstFilePath, dstRelativePath);

    return YES;
}

@end

NS_ASSUME_NONNULL_END
