//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportJob.h"
#import "OWSBackupIO.h"
#import "OWSDatabaseMigration.h"
#import "OWSDatabaseMigrationRunner.h"
#import "Signal-Swift.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ImportDatabaseKeySpec = @"kOWSBackup_ImportDatabaseKeySpec";

#pragma mark -

@interface OWSBackupImportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

@property (nonatomic) OWSBackupIO *backupIO;

@property (nonatomic) OWSBackupManifestContents *manifest;

@end

#pragma mark -

@implementation OWSBackupImportJob

#pragma mark - Dependencies

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager shared];
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSBackup *)backup
{
    OWSAssertDebug(AppEnvironment.shared.backup);

    return AppEnvironment.shared.backup;
}

- (OWSBackupLazyRestore *)backupLazyRestore
{
    return AppEnvironment.shared.backupLazyRestore;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (NSArray<OWSBackupFragment *> *)databaseItems
{
    OWSAssertDebug(self.manifest);

    return self.manifest.databaseItems;
}

- (NSArray<OWSBackupFragment *> *)attachmentsItems
{
    OWSAssertDebug(self.manifest);

    return self.manifest.attachmentsItems;
}

- (void)start
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self updateProgressWithDescription:nil progress:nil];

    [self.backup ensureCloudKitAccess]
        .thenInBackground(^{
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_CONFIGURATION",
                                                    @"Indicates that the backup import is being configured.")
                                       progress:nil];

            return [self configureImport];
        })
        .thenInBackground(^{
            if (self.isComplete) {
                return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
            }

            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_IMPORT",
                                                    @"Indicates that the backup import data is being imported.")
                                       progress:nil];

            return [self downloadAndProcessManifestWithBackupIO:self.backupIO];
        })
        .thenInBackground(^(OWSBackupManifestContents *manifest) {
            OWSCAssertDebug(manifest.databaseItems.count > 0);
            OWSCAssertDebug(manifest.attachmentsItems);

            self.manifest = manifest;

            return [self downloadAndProcessImport];
        })
        .catch(^(NSError *error) {
            [self
                failWithErrorDescription:NSLocalizedString(@"BACKUP_IMPORT_ERROR_COULD_NOT_IMPORT",
                                             @"Error indicating the backup import could not import the user's data.")];
        });
}

- (AnyPromise *)downloadAndProcessImport
{
    OWSAssertDebug(self.databaseItems);
    OWSAssertDebug(self.attachmentsItems);

    // These items should be downloaded immediately.
    NSMutableArray<OWSBackupFragment *> *allItems = [NSMutableArray new];
    [allItems addObjectsFromArray:self.databaseItems];

    // Make a copy of the blockingItems before we add
    // the optional items.
    NSArray<OWSBackupFragment *> *blockingItems = [allItems copy];

    // Local profile avatars are optional in the sense that if their
    // download fails, we want to proceed with the import.
    if (self.manifest.localProfileAvatarItem) {
        [allItems addObject:self.manifest.localProfileAvatarItem];
    }

    // Attachment items can be downloaded later;
    // they will can be lazy-restored.
    [allItems addObjectsFromArray:self.attachmentsItems];

    // Record metadata for all items, so that we can re-use them in incremental backups after the restore.
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (OWSBackupFragment *item in allItems) {
            [item anyUpsertWithTransaction:transaction];
        }
    });

    return [self downloadFilesFromCloud:blockingItems]
        .thenInBackground(^{
            return [self restoreDatabase];
        })
        .thenInBackground(^{
            return [self ensureMigrations];
        })
        .thenInBackground(^{
            return [self restoreLocalProfile];
        })
        .thenInBackground(^{
            return [self restoreAttachmentFiles];
        })
        .then(^{
            // Kick off lazy restore on main thread.
            [self.backupLazyRestore clearCompleteAndRunIfNecessary];

            [self.profileManager fetchLocalUsersProfile];

            // Make sure backup is enabled once we complete
            // a backup restore.
            [OWSBackup.shared setIsBackupEnabled:YES];
        })
        .thenInBackground(^{
            return [self.tsAccountManager updateAccountAttributes];
        })
        .thenInBackground(^{
            [self succeed];
        });
}

- (AnyPromise *)configureImport
{
    OWSLogVerbose(@"");

    if (![self ensureJobTempDir]) {
        OWSFailDebug(@"Could not create jobTempDirPath.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not create jobTempDirPath.")];
    }

    self.backupIO = [[OWSBackupIO alloc] initWithJobTempDirPath:self.jobTempDirPath];

    return [AnyPromise promiseWithValue:@(1)];
}

- (AnyPromise *)downloadFilesFromCloud:(NSArray<OWSBackupFragment *> *)items
{
    OWSAssertDebug(items.count > 0);

    OWSLogVerbose(@"");

    NSUInteger recordCount = items.count;

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    if (items.count < 1) {
        // All downloads are complete; exit.
        return [AnyPromise promiseWithValue:@(1)];
    }

    AnyPromise *promise = [AnyPromise promiseWithValue:@(1)];
    for (OWSBackupFragment *item in items) {
        promise = promise
                      .thenInBackground(^{
                          CGFloat progress
                              = (recordCount > 0 ? ((recordCount - items.count) / (CGFloat)recordCount) : 0.f);
                          [self updateProgressWithDescription:
                                    NSLocalizedString(@"BACKUP_IMPORT_PHASE_DOWNLOAD",
                                        @"Indicates that the backup import data is being downloaded.")
                                                     progress:@(progress)];
                      })
                      .thenInBackground(^{
                          return [self downloadFileFromCloud:item];
                      });
    }

    return promise;
}

- (AnyPromise *)downloadFileFromCloud:(OWSBackupFragment *)item
{
    OWSAssertDebug(item);

    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        // TODO: Use a predictable file path so that multiple "import backup" attempts
        // will leverage successful file downloads from previous attempts.
        //
        // TODO: This will also require imports using a predictable jobTempDirPath.
        NSString *tempFilePath = [self.jobTempDirPath stringByAppendingPathComponent:item.recordName];

        // Skip redundant file download.
        if ([NSFileManager.defaultManager fileExistsAtPath:tempFilePath]) {
            [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];

            item.downloadFilePath = tempFilePath;

            return resolve(@(1));
        }

        [OWSBackupAPI downloadFileFromCloudObjcWithRecordName:item.recordName
                                                    toFileUrl:[NSURL fileURLWithPath:tempFilePath]]
            .thenInBackground(^{
                [OWSFileSystem protectFileOrFolderAtPath:tempFilePath];
                item.downloadFilePath = tempFilePath;

                resolve(@(1));
            })
            .catchInBackground(^(NSError *error) {
                resolve(error);
            });
    }];
}

- (AnyPromise *)restoreLocalProfile
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    AnyPromise *promise = [AnyPromise promiseWithValue:@(1)];

    if (self.manifest.localProfileAvatarItem) {
        promise = promise.thenInBackground(^{
            return
                [self downloadFileFromCloud:self.manifest.localProfileAvatarItem].catchInBackground(^(NSError *error) {
                    OWSLogInfo(@"Ignoring error; profiles are optional: %@", error);
                });
        });
    }

    promise = promise.thenInBackground(^{
        return [self applyLocalProfile];
    });
    return promise;
}

- (AnyPromise *)applyLocalProfile
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    NSString *_Nullable localProfileGivenName = self.manifest.localProfileGivenName;
    NSString *_Nullable localProfileFamilyName = self.manifest.localProfileFamilyName;
    NSData *_Nullable localProfileAvatarData = [self tryToLoadLocalProfileAvatarData];

    OWSLogVerbose(@"local profile given name: %@, family name: %@, avatar: %d",
        localProfileGivenName,
        localProfileFamilyName,
        localProfileAvatarData != nil);

    if (localProfileGivenName.length < 1 && !localProfileAvatarData) {
        return [AnyPromise promiseWithValue:@(1)];
    }

    return [OWSProfileManager updateLocalProfilePromiseObjWithProfileGivenName:localProfileGivenName
                                                             profileFamilyName:localProfileFamilyName
                                                             profileAvatarData:localProfileAvatarData]
        .catch(^(NSError *error) {
            OWSFailDebug(@"Error: %@", error);
            // Ignore errors related to local profile.
        });
}

- (nullable NSData *)tryToLoadLocalProfileAvatarData
{
    if (!self.manifest.localProfileAvatarItem) {
        return nil;
    }
    if (!self.manifest.localProfileAvatarItem.downloadFilePath) {
        // Download of the avatar failed.
        // We can safely ignore errors related to local profile.
        OWSLogError(@"local profile avatar was not downloaded.");
        return nil;
    }
    OWSBackupFragment *item = self.manifest.localProfileAvatarItem;
    if (item.recordName.length < 1) {
        OWSFailDebug(@"item missing record name.");
        return nil;
    }

    @autoreleasepool {
        NSData *_Nullable data =
            [self.backupIO decryptFileAsData:item.downloadFilePath encryptionKey:item.encryptionKey];
        if (!data) {
            OWSLogError(@"could not decrypt local profile avatar.");
            // Ignore errors related to local profile.
            return nil;
        }
        return data;
    }
}

- (AnyPromise *)restoreAttachmentFiles
{
    OWSLogVerbose(@": %zd", self.attachmentsItems.count);

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    __block NSUInteger count = 0;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (OWSBackupFragment *item in self.attachmentsItems) {
            if (self.isComplete) {
                return;
            }
            if (item.recordName.length < 1) {
                OWSLogError(@"attachment was not downloaded.");
                // Attachment-related errors are recoverable and can be ignored.
                continue;
            }
            if (item.attachmentId.length < 1) {
                OWSLogError(@"attachment missing attachment id.");
                // Attachment-related errors are recoverable and can be ignored.
                continue;
            }
            if (item.relativeFilePath.length < 1) {
                OWSLogError(@"attachment missing relative file path.");
                // Attachment-related errors are recoverable and can be ignored.
                continue;
            }
            TSAttachment *_Nullable attachment =
                [TSAttachmentPointer anyFetchWithUniqueId:item.attachmentId transaction:transaction];
            if (!attachment) {
                OWSLogError(@"attachment to restore could not be found.");
                // Attachment-related errors are recoverable and can be ignored.
                continue;
            }
            if (![attachment isKindOfClass:[TSAttachmentPointer class]]) {
                OWSFailDebug(@"attachment has unexpected type: %@.", attachment.class);
                // Attachment-related errors are recoverable and can be ignored.
                continue;
            }
            TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)attachment;
            [attachmentPointer markForLazyRestoreWithFragment:item transaction:transaction];
            count++;
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_RESTORING_FILES",
                                                    @"Indicates that the backup import data is being restored.")
                                       progress:@(count / (CGFloat)self.attachmentsItems.count)];
        }
    });

    OWSLogError(@"enqueued lazy restore of %zd files.", count);

    return [AnyPromise promiseWithValue:@(1)];
}

- (AnyPromise *)restoreDatabase
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    NSMutableDictionary<NSString *, NSNumber *> *restoredEntityCounts = [NSMutableDictionary new];
    __block unsigned long long copiedEntities = 0;
    __block BOOL aborted = NO;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
    // POST GRDB TODO: We need to totally rework this, post GRDB.

#ifdef GRDB_BACKUP
        // Order matters here.
        NSArray<NSString *> *collectionsToRestore = @[
            [TSThread collection],
            [TSAttachment collection],
            // Interactions refer to threads and attachments,
            // so copy them afterward.
            [TSInteraction collection],
            [OWSDatabaseMigration collection],
        ];

        for (NSString *collection in collectionsToRestore) {
            if ([collection isEqualToString:[OWSDatabaseMigration collection]]) {
                // It's okay if there are existing migrations; we'll clear those
                // before restoring.
                continue;
            }
            if ([transaction numberOfKeysInCollection:collection] > 0) {
                OWSLogError(@"unexpected contents in database (%@).", collection);
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
        for (OWSBackupFragment *item in self.databaseItems) {
            if (self.isComplete) {
                return;
            }
            if (item.recordName.length < 1) {
                OWSLogError(@"database snapshot was not downloaded.");
                // Attachment-related errors are recoverable and can be ignored.
                // Database-related errors are unrecoverable.
                aborted = YES;
                return;
            }
            if (!item.uncompressedDataLength || item.uncompressedDataLength.unsignedIntValue < 1) {
                OWSLogError(@"database snapshot missing size.");
                // Attachment-related errors are recoverable and can be ignored.
                // Database-related errors are unrecoverable.
                aborted = YES;
                return;
            }

            count++;
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_RESTORING_DATABASE",
                                                    @"Indicates that the backup database is being restored.")
                                       progress:@(count / (CGFloat)self.databaseItems.count)];

            @autoreleasepool {
                NSData *_Nullable compressedData =
                    [self.backupIO decryptFileAsData:item.downloadFilePath encryptionKey:item.encryptionKey];
                if (!compressedData) {
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return;
                }
                NSData *_Nullable uncompressedData =
                    [self.backupIO decompressData:compressedData
                           uncompressedDataLength:item.uncompressedDataLength.unsignedIntValue];
                if (!uncompressedData) {
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return;
                }
                NSError *error;
                SignalIOSProtoBackupSnapshot *_Nullable entities =
                    [SignalIOSProtoBackupSnapshot parseData:uncompressedData error:&error];
                if (!entities || error) {
                    OWSLogError(@"could not parse proto: %@.", error);
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return;
                }
                if (!entities || entities.entity.count < 1) {
                    OWSLogError(@"missing entities.");
                    // Database-related errors are unrecoverable.
                    aborted = YES;
                    return;
                }
                for (SignalIOSProtoBackupSnapshotBackupEntity *entity in entities.entity) {
                    NSData *_Nullable entityData = entity.entityData;
                    if (entityData.length < 1) {
                        OWSLogError(@"missing entity data.");
                        // Database-related errors are unrecoverable.
                        aborted = YES;
                        return;
                    }

                    NSString *_Nullable collection = entity.collection;
                    if (collection.length < 1) {
                        OWSLogError(@"missing collection.");
                        // Database-related errors are unrecoverable.
                        aborted = YES;
                        return;
                    }

                    NSString *_Nullable key = entity.key;
                    if (key.length < 1) {
                        OWSLogError(@"missing key.");
                        // Database-related errors are unrecoverable.
                        aborted = YES;
                        return;
                    }

                    __block NSObject *object = nil;
                    @try {
                        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:entityData];
                        object = [unarchiver decodeObjectForKey:@"root"];
                        if (![object isKindOfClass:[object class]]) {
                            OWSLogError(@"invalid decoded entity: %@.", [object class]);
                            // Database-related errors are unrecoverable.
                            aborted = YES;
                            return;
                        }
                    } @catch (NSException *exception) {
                        OWSLogError(@"could not decode entity.");
                        // Database-related errors are unrecoverable.
                        aborted = YES;
                        return;
                    }

                    [transaction setObject:object forKey:key inCollection:collection];
                    copiedEntities++;
                    NSUInteger restoredEntityCount = restoredEntityCounts[collection].unsignedIntValue;
                    restoredEntityCounts[collection] = @(restoredEntityCount + 1);
                }
            }
        }
#endif
    });

    if (aborted) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import failed.")];
    }
    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    for (NSString *collection in restoredEntityCounts) {
        OWSLogInfo(@"copied %@: %@", collection, restoredEntityCounts[collection]);
    }
    OWSLogInfo(@"copiedEntities: %llu", copiedEntities);

    [self.databaseStorage logFileSizes];

    return [AnyPromise promiseWithValue:@(1)];
}

- (AnyPromise *)ensureMigrations
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup import no longer active.")];
    }

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_IMPORT_PHASE_FINALIZING",
                                            @"Indicates that the backup import data is being finalized.")
                               progress:nil];


    // It's okay that we do this in a separate transaction from the
    // restoration of backup contents.  If some of migrations don't
    // complete, they'll be run the next time the app launches.
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[OWSDatabaseMigrationRunner alloc] init] runAllOutstandingWithCompletion:^{
                    resolve(@(1));
                }];
        });
    }];
    return promise;
}

@end

NS_ASSUME_NONNULL_END
