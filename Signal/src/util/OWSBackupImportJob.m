//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportJob.h"
#import "OWSBackupEncryption.h"
#import "OWSDatabaseMigration.h"
#import "OWSDatabaseMigrationRunner.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/NSData+Base64.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ImportDatabaseKeySpec = @"kOWSBackup_ImportDatabaseKeySpec";

#pragma mark -

@interface OWSBackupImportItem : NSObject

@property (nonatomic) NSString *recordName;

@property (nonatomic) NSData *encryptionKey;

@property (nonatomic, nullable) NSString *relativeFilePath;

@property (nonatomic, nullable) NSString *downloadFilePath;

@property (nonatomic, nullable) NSNumber *uncompressedDataLength;

@end

#pragma mark -

@implementation OWSBackupImportItem

@end

#pragma mark -

@interface OWSBackupImportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

@property (nonatomic) OWSBackupEncryption *encryption;

@property (nonatomic) NSArray<OWSBackupImportItem *> *databaseItems;
@property (nonatomic) NSArray<OWSBackupImportItem *> *attachmentsItems;

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

        OWSAssert(self.databaseItems);
        OWSAssert(self.attachmentsItems);
        NSMutableArray<OWSBackupImportItem *> *allItems = [NSMutableArray new];
        [allItems addObjectsFromArray:self.databaseItems];
        [allItems addObjectsFromArray:self.attachmentsItems];
        [weakSelf
            downloadFilesFromCloud:allItems
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

    self.encryption = [[OWSBackupEncryption alloc] initWithJobTempDirPath:self.jobTempDirPath];

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
            OWSProdLogAndFail(@"%@ Could not download manifest.", weakSelf.logTag);
            completion(error);
        }];
}

- (void)processManifest:(NSData *)manifestDataEncrypted completion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);
    OWSAssert(self.encryption);

    if (self.isComplete) {
        return;
    }

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSData *_Nullable manifestDataDecrypted =
        [self.encryption decryptDataAsData:manifestDataEncrypted encryptionKey:self.delegate.backupEncryptionKey];
    if (!manifestDataDecrypted) {
        OWSProdLogAndFail(@"%@ Could not decrypt manifest.", self.logTag);
        return completion(NO);
    }

    NSError *error;
    NSDictionary<NSString *, id> *_Nullable json =
        [NSJSONSerialization JSONObjectWithData:manifestDataDecrypted options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OWSProdLogAndFail(@"%@ Could not download manifest.", self.logTag);
        return completion(NO);
    }

    DDLogVerbose(@"%@ json: %@", self.logTag, json);

    NSArray<OWSBackupImportItem *> *_Nullable databaseItems =
        [self parseItems:json key:kOWSBackup_ManifestKey_DatabaseFiles];
    if (!databaseItems) {
        return completion(NO);
    }
    NSArray<OWSBackupImportItem *> *_Nullable attachmentsItems =
        [self parseItems:json key:kOWSBackup_ManifestKey_AttachmentFiles];
    if (!attachmentsItems) {
        return completion(NO);
    }

    self.databaseItems = databaseItems;
    self.attachmentsItems = attachmentsItems;

    return completion(YES);
}

- (nullable NSArray<OWSBackupImportItem *> *)parseItems:(id)json key:(NSString *)key
{
    OWSAssert(json);
    OWSAssert(key.length);

    if (![json isKindOfClass:[NSArray class]]) {
        OWSProdLogAndFail(@"%@ manifest has invalid data: %@.", self.logTag, key);
        return nil;
    }
    NSArray *itemMaps = json[key];
    if (![itemMaps isKindOfClass:[NSArray class]]) {
        OWSProdLogAndFail(@"%@ manifest has invalid data: %@.", self.logTag, key);
        return nil;
    }
    NSMutableArray<OWSBackupImportItem *> *items = [NSMutableArray new];
    for (NSDictionary *itemMap in itemMaps) {
        if (![itemMap isKindOfClass:[NSDictionary class]]) {
            OWSProdLogAndFail(@"%@ manifest has invalid item: %@.", self.logTag, key);
            return nil;
        }
        NSString *_Nullable recordName = itemMap[kOWSBackup_ManifestKey_RecordName];
        NSString *_Nullable encryptionKeyString = itemMap[kOWSBackup_ManifestKey_EncryptionKey];
        NSString *_Nullable relativeFilePath = itemMap[kOWSBackup_ManifestKey_RelativeFilePath];
        NSNumber *_Nullable uncompressedDataLength = itemMap[kOWSBackup_ManifestKey_DataSize];
        if (![recordName isKindOfClass:[NSString class]]) {
            OWSProdLogAndFail(@"%@ manifest has invalid recordName: %@.", self.logTag, key);
            return nil;
        }
        if (![encryptionKeyString isKindOfClass:[NSString class]]) {
            OWSProdLogAndFail(@"%@ manifest has invalid encryptionKey: %@.", self.logTag, key);
            return nil;
        }
        // relativeFilePath is an optional field.
        if (relativeFilePath && ![relativeFilePath isKindOfClass:[NSString class]]) {
            OWSProdLogAndFail(@"%@ manifest has invalid relativeFilePath: %@.", self.logTag, key);
            return nil;
        }
        NSData *_Nullable encryptionKey = [NSData dataFromBase64String:encryptionKeyString];
        if (!encryptionKey) {
            OWSProdLogAndFail(@"%@ manifest has corrupt encryptionKey: %@.", self.logTag, key);
            return nil;
        }
        // uncompressedDataLength is an optional field.
        if (uncompressedDataLength && ![uncompressedDataLength isKindOfClass:[NSNumber class]]) {
            OWSProdLogAndFail(@"%@ manifest has invalid uncompressedDataLength: %@.", self.logTag, key);
            return nil;
        }

        OWSBackupImportItem *item = [OWSBackupImportItem new];
        item.recordName = recordName;
        item.encryptionKey = encryptionKey;
        item.relativeFilePath = relativeFilePath;
        item.uncompressedDataLength = uncompressedDataLength;
        [items addObject:item];
    }
    return items;
}

- (void)downloadFilesFromCloud:(NSMutableArray<OWSBackupImportItem *> *)items
                    completion:(OWSBackupJobCompletion)completion
{
    OWSAssert(items.count > 0);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self downloadNextItemFromCloud:items recordCount:items.count completion:completion];
}

- (void)downloadNextItemFromCloud:(NSMutableArray<OWSBackupImportItem *> *)items
                      recordCount:(NSUInteger)recordCount
                       completion:(OWSBackupJobCompletion)completion
{
    OWSAssert(items);
    OWSAssert(completion);

    if (self.isComplete) {
        // Job was aborted.
        return completion(nil);
    }

    if (items.count < 1) {
        // All downloads are complete; exit.
        return completion(nil);
    }
    OWSBackupImportItem *item = items.lastObject;
    [items removeLastObject];

    CGFloat progress = (recordCount > 0 ? ((recordCount - items.count) / (CGFloat)recordCount) : 0.f);
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_DOWNLOAD",
                                            @"Indicates that the backup import data is being downloaded.")
                               progress:@(progress)];

    // Use a predictable file path so that multiple "import backup" attempts
    // will leverage successful file downloads from previous attempts.
    //
    // TODO: This will also require imports using a predictable jobTempDirPath.
    NSString *tempFilePath = [self.jobTempDirPath stringByAppendingPathComponent:item.recordName];

    // Skip redundant file download.
    if ([NSFileManager.defaultManager fileExistsAtPath:tempFilePath]) {
        [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];

        item.downloadFilePath = tempFilePath;

        [self downloadNextItemFromCloud:items recordCount:recordCount completion:completion];
        return;
    }

    __weak OWSBackupImportJob *weakSelf = self;
    [OWSBackupAPI downloadFileFromCloudWithRecordName:item.recordName
        toFileUrl:[NSURL fileURLWithPath:tempFilePath]
        success:^{
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];
                item.downloadFilePath = tempFilePath;

                [weakSelf downloadNextItemFromCloud:items recordCount:recordCount completion:completion];
            });
        }
        failure:^(NSError *error) {
            completion(error);
        }];
}

- (void)restoreAttachmentFiles
{
    DDLogVerbose(@"%@ %s: %zd", self.logTag, __PRETTY_FUNCTION__, self.attachmentsItems.count);

    NSString *attachmentsDirPath = [TSAttachmentStream attachmentsFolder];

    NSUInteger count = 0;
    for (OWSBackupImportItem *item in self.attachmentsItems) {
        if (self.isComplete) {
            return;
        }
        if (item.recordName.length < 1) {
            DDLogError(@"%@ attachment was not downloaded.", self.logTag);
            // Attachment-related errors are recoverable and can be ignored.
            continue;
        }
        if (item.relativeFilePath.length < 1) {
            DDLogError(@"%@ attachment missing relative file path.", self.logTag);
            // Attachment-related errors are recoverable and can be ignored.
            continue;
        }

        count++;
        [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_RESTORING_FILES",
                                                @"Indicates that the backup import data is being restored.")
                                   progress:@(count / (CGFloat)self.attachmentsItems.count)];

        NSString *dstFilePath = [attachmentsDirPath stringByAppendingPathComponent:item.relativeFilePath];
        if ([NSFileManager.defaultManager fileExistsAtPath:dstFilePath]) {
            DDLogError(@"%@ skipping redundant file restore: %@.", self.logTag, dstFilePath);
            continue;
        }
        if (![self.encryption decryptFileAsFile:item.downloadFilePath
                                    dstFilePath:dstFilePath
                                  encryptionKey:item.encryptionKey]) {
            DDLogError(@"%@ attachment could not be restored.", self.logTag);
            // Attachment-related errors are recoverable and can be ignored.
            continue;
        }

        DDLogError(@"%@ restored file: %@.", self.logTag, item.relativeFilePath);
    }
}

- (void)restoreDatabase:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (self.isComplete) {
        return completion(NO);
    }

    YapDatabaseConnection *_Nullable dbConnection = self.primaryStorage.newDatabaseConnection;
    if (!dbConnection) {
        OWSProdLogAndFail(@"%@ Could not create dbConnection.", self.logTag);
        return completion(NO);
    }

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
    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSString *collection in collectionsToRestore) {
            if ([collection isEqualToString:[OWSDatabaseMigration collection]]) {
                // It's okay if there are existing migrations; we'll clear those
                // before restoring.
                continue;
            }
            if ([transaction numberOfKeysInCollection:collection] > 0) {
                DDLogError(@"%@ unexpected contents in database (%@).", self.logTag, collection);
            }
        }

        // Clear existing database contents.
        //
        // This should be safe since we only ever import into an empty database.
        //
        // Note that if the app receives a message after registering and before restoring
        // backup, it will be lost.
        //
        // Note that this will clear all migrations.
        for (NSString *collection in collectionsToRestore) {
            [transaction removeAllObjectsInCollection:collection];
        }

        NSUInteger count = 0;
        for (OWSBackupImportItem *item in self.databaseItems) {
            if (self.isComplete) {
                return;
            }
            if (item.recordName.length < 1) {
                DDLogError(@"%@ database snapshot was not downloaded.", self.logTag);
                // Attachment-related errors are recoverable and can be ignored.
                // Database-related errors are unrecoverable.
                aborted = YES;
                return completion(NO);
            }
            if (!item.uncompressedDataLength || item.uncompressedDataLength.unsignedIntValue < 1) {
                DDLogError(@"%@ database snapshot missing size.", self.logTag);
                // Attachment-related errors are recoverable and can be ignored.
                // Database-related errors are unrecoverable.
                aborted = YES;
                return completion(NO);
            }

            count++;
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_RESTORING_DATABASE",
                                                    @"Indicates that the backup database is being restored.")
                                       progress:@(count / (CGFloat)self.databaseItems.count)];

            NSData *_Nullable compressedData =
                [self.encryption decryptFileAsData:item.downloadFilePath encryptionKey:item.encryptionKey];
            if (!compressedData) {
                // Database-related errors are unrecoverable.
                aborted = YES;
                return completion(NO);
            }
            NSData *_Nullable uncompressedData =
                [self.encryption decompressData:compressedData
                         uncompressedDataLength:item.uncompressedDataLength.unsignedIntValue];
            if (!uncompressedData) {
                // Database-related errors are unrecoverable.
                aborted = YES;
                return completion(NO);
            }
            OWSSignalServiceProtosBackupSnapshot *_Nullable entities =
                [OWSSignalServiceProtosBackupSnapshot parseFromData:uncompressedData];
            if (!entities || entities.entity.count < 1) {
                DDLogError(@"%@ missing entities.", self.logTag);
                // Database-related errors are unrecoverable.
                aborted = YES;
                return completion(NO);
            }
            for (OWSSignalServiceProtosBackupSnapshotBackupEntity *entity in entities.entity) {
                NSData *_Nullable entityData = entity.entityData;
                if (entityData.length < 1) {
                    DDLogError(@"%@ missing entity data.", self.logTag);
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return completion(NO);
                }

                __block TSYapDatabaseObject *object = nil;
                @try {
                    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:entityData];
                    object = [unarchiver decodeObjectForKey:@"root"];
                    if (![object isKindOfClass:[object class]]) {
                        DDLogError(@"%@ invalid decoded entity: %@.", self.logTag, [object class]);
                        // Database-related errors are unrecoverable.
                        aborted = YES;
                        return completion(NO);
                    }
                } @catch (NSException *exception) {
                    DDLogError(@"%@ could not decode entity.", self.logTag);
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return completion(NO);
                }

                [object saveWithTransaction:transaction];
                copiedEntities++;
                NSString *collection = [object.class collection];
                NSUInteger restoredEntityCount = restoredEntityCounts[collection].unsignedIntValue;
                restoredEntityCounts[collection] = @(restoredEntityCount + 1);
            }
        }
    }];

    if (self.isComplete || aborted) {
        return;
    }

    for (NSString *collection in restoredEntityCounts) {
        DDLogInfo(@"%@ copied %@: %@", self.logTag, collection, restoredEntityCounts[collection]);
    }
    DDLogInfo(@"%@ copiedEntities: %llu", self.logTag, copiedEntities);

    [self.primaryStorage logFileSizes];

    completion(YES);
}

- (void)ensureMigrations:(OWSBackupJobBoolCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_FINALIZING",
                                            @"Indicates that the backup import data is being finalized.")
                               progress:nil];


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

@end

NS_ASSUME_NONNULL_END
