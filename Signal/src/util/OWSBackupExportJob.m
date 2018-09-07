//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExportJob.h"
#import "OWSBackupIO.h"
#import "OWSDatabaseMigration.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSAttachmentExport;

@interface OWSBackupExportItem : NSObject

@property (nonatomic) OWSBackupEncryptedItem *encryptedItem;

@property (nonatomic) NSString *recordName;

// This property is optional and is only used for attachments.
@property (nonatomic, nullable) OWSAttachmentExport *attachmentExport;

// This property is optional.
//
// See comments in `OWSBackupIO`.
@property (nonatomic, nullable) NSNumber *uncompressedDataLength;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSBackupExportItem

- (instancetype)initWithEncryptedItem:(OWSBackupEncryptedItem *)encryptedItem
{
    if (!(self = [super init])) {
        return self;
    }

    OWSAssertDebug(encryptedItem);

    self.encryptedItem = encryptedItem;

    return self;
}

@end

#pragma mark -

// Used to serialize database snapshot contents.
// Writes db entities using protobufs into snapshot fragments.
// Snapshot fragments are compressed (they compress _very well_,
// around 20x smaller) then encrypted.  Ordering matters in
// snapshot contents (entities should be restored in the same
// order they are serialized), so we are always careful to preserve
// ordering of entities within a snapshot AND ordering of snapshot
// fragments within a bakckup.
//
// This stream is used to write entities one at a time and takes
// care of sharding them into fragments, compressing and encrypting
// those fragments.  Fragment size is fixed to reduce worst case
// memory usage.
@interface OWSDBExportStream : NSObject

@property (nonatomic) OWSBackupIO *backupIO;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *exportItems;

@property (nonatomic, nullable) SignalIOSProtoBackupSnapshotBuilder *backupSnapshotBuilder;

@property (nonatomic) NSUInteger cachedItemCount;

@property (nonatomic) NSUInteger totalItemCount;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSDBExportStream

- (instancetype)initWithBackupIO:(OWSBackupIO *)backupIO
{
    if (!(self = [super init])) {
        return self;
    }

    OWSAssertDebug(backupIO);

    self.exportItems = [NSMutableArray new];
    self.backupIO = backupIO;

    return self;
}


// It isn't strictly necessary to capture the entity type (the importer doesn't
// use this state), but I think it'll be helpful to have around to future-proof
// this work, help with debugging issue, etc.
- (BOOL)writeObject:(TSYapDatabaseObject *)object entityType:(SignalIOSProtoBackupSnapshotBackupEntityType)entityType
{
    OWSAssertDebug(object);

    NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:object];
    if (!data) {
        OWSFailDebug(@"couldn't serialize database object: %@", [object class]);
        return NO;
    }

    if (!self.backupSnapshotBuilder) {
        self.backupSnapshotBuilder = [SignalIOSProtoBackupSnapshotBuilder new];
    }

    SignalIOSProtoBackupSnapshotBackupEntityBuilder *entityBuilder =
        [[SignalIOSProtoBackupSnapshotBackupEntityBuilder alloc] initWithType:entityType entityData:data];

    NSError *error;
    SignalIOSProtoBackupSnapshotBackupEntity *_Nullable entity = [entityBuilder buildAndReturnError:&error];
    if (!entity || error) {
        OWSFailDebug(@"couldn't build proto: %@", error);
        return NO;
    }

    [self.backupSnapshotBuilder addEntity:entity];

    self.cachedItemCount = self.cachedItemCount + 1;
    self.totalItemCount = self.totalItemCount + 1;

    static const int kMaxDBSnapshotSize = 1000;
    if (self.cachedItemCount > kMaxDBSnapshotSize) {
        @autoreleasepool {
            return [self flush];
        }
    }

    return YES;
}

// Write cached data to disk, if necessary.
//
// Returns YES on success.
- (BOOL)flush
{
    if (!self.backupSnapshotBuilder) {
        // No data to flush to disk.
        return YES;
    }

    // Try to release allocated buffers ASAP.
    @autoreleasepool {
        NSError *error;
        NSData *_Nullable uncompressedData = [self.backupSnapshotBuilder buildSerializedDataAndReturnError:&error];
        if (!uncompressedData || error) {
            OWSFailDebug(@"couldn't serialize proto: %@", error);
            return NO;
        }

        NSUInteger uncompressedDataLength = uncompressedData.length;
        self.backupSnapshotBuilder = nil;
        self.cachedItemCount = 0;
        if (!uncompressedData) {
            OWSFailDebug(@"couldn't convert database snapshot to data.");
            return NO;
        }

        NSData *compressedData = [self.backupIO compressData:uncompressedData];

        OWSBackupEncryptedItem *_Nullable encryptedItem = [self.backupIO encryptDataAsTempFile:compressedData];
        if (!encryptedItem) {
            OWSFailDebug(@"couldn't encrypt database snapshot.");
            return NO;
        }

        OWSBackupExportItem *exportItem = [[OWSBackupExportItem alloc] initWithEncryptedItem:encryptedItem];
        exportItem.uncompressedDataLength = @(uncompressedDataLength);
        [self.exportItems addObject:exportItem];
    }

    return YES;
}

@end

#pragma mark -

// This class is used to:
//
// * Lazy-encrypt and eagerly cleanup attachment uploads.
//   To reduce disk footprint of backup export process,
//   we only want to have one attachment export on disk
//   at a time.
@interface OWSAttachmentExport : NSObject

@property (nonatomic) OWSBackupIO *backupIO;
@property (nonatomic) NSString *attachmentId;
@property (nonatomic) NSString *attachmentFilePath;
@property (nonatomic, nullable) NSString *relativeFilePath;
@property (nonatomic) OWSBackupEncryptedItem *encryptedItem;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSAttachmentExport

- (instancetype)initWithBackupIO:(OWSBackupIO *)backupIO
                    attachmentId:(NSString *)attachmentId
              attachmentFilePath:(NSString *)attachmentFilePath
{
    if (!(self = [super init])) {
        return self;
    }

    OWSAssertDebug(backupIO);
    OWSAssertDebug(attachmentId.length > 0);
    OWSAssertDebug(attachmentFilePath.length > 0);

    self.backupIO = backupIO;
    self.attachmentId = attachmentId;
    self.attachmentFilePath = attachmentFilePath;

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [self cleanUp];
}

// On success, encryptedItem will be non-nil.
//
// Returns YES on success.
- (BOOL)prepareForUpload
{
    OWSAssertDebug(self.attachmentId.length > 0);
    OWSAssertDebug(self.attachmentFilePath.length > 0);

    NSString *attachmentsDirPath = [TSAttachmentStream attachmentsFolder];
    if (![self.attachmentFilePath hasPrefix:attachmentsDirPath]) {
        OWSFailDebug(@"attachment has unexpected path: %@", self.attachmentFilePath);
        return NO;
    }
    NSString *relativeFilePath = [self.attachmentFilePath substringFromIndex:attachmentsDirPath.length];
    NSString *pathSeparator = @"/";
    if ([relativeFilePath hasPrefix:pathSeparator]) {
        relativeFilePath = [relativeFilePath substringFromIndex:pathSeparator.length];
    }
    self.relativeFilePath = relativeFilePath;

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self.backupIO encryptFileAsTempFile:self.attachmentFilePath];
    if (!encryptedItem) {
        OWSFailDebug(@"attachment could not be encrypted: %@", self.attachmentFilePath);
        return NO;
    }
    self.encryptedItem = encryptedItem;
    return YES;
}

// Returns YES on success.
- (BOOL)cleanUp
{
    return [OWSFileSystem deleteFileIfExists:self.encryptedItem.filePath];
}

@end

#pragma mark -

@interface OWSBackupExportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

@property (nonatomic) OWSBackupIO *backupIO;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *unsavedDatabaseItems;

@property (nonatomic) NSMutableArray<OWSAttachmentExport *> *unsavedAttachmentExports;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *savedDatabaseItems;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *savedAttachmentItems;

@property (nonatomic, nullable) OWSBackupExportItem *manifestItem;

// If we are replacing an existing backup, we use some of its contents for continuity.
@property (nonatomic, nullable) NSSet<NSString *> *lastValidRecordNames;

@end

#pragma mark -

@implementation OWSBackupExportJob

- (void)startAsync
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self updateProgressWithDescription:nil progress:nil];

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI checkCloudKitAccessWithCompletion:^(BOOL hasAccess) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (hasAccess) {
                [weakSelf start];
            } else {
                [weakSelf failWithErrorDescription:
                              NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                                  @"Error indicating the backup export could not export the user's data.")];
            }
        });
    }];
}

- (void)start
{
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CONFIGURATION",
                                            @"Indicates that the backup export is being configured.")
                               progress:nil];

    __weak OWSBackupExportJob *weakSelf = self;
    [self configureExportWithCompletion:^(BOOL configureExportSuccess) {
        if (!configureExportSuccess) {
            [self
                failWithErrorDescription:NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                                             @"Error indicating the backup export could not export the user's data.")];
            return;
        }

        if (self.isComplete) {
            return;
        }
        [self fetchAllRecordsWithCompletion:^(BOOL tryToFetchManifestSuccess) {
            if (!tryToFetchManifestSuccess) {
                [self failWithErrorDescription:
                          NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                              @"Error indicating the backup export could not export the user's data.")];
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
                              @"Error indicating the backup export could not export the user's data.")];
                return;
            }
            if (self.isComplete) {
                return;
            }
            [self saveToCloudWithCompletion:^(NSError *_Nullable saveError) {
                if (saveError) {
                    [weakSelf failWithError:saveError];
                    return;
                }
                [self cleanUpWithCompletion:^(NSError *_Nullable cleanUpError) {
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

- (void)configureExportWithCompletion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssertDebug(completion);

    OWSLogVerbose(@"");

    if (![self ensureJobTempDir]) {
        OWSFailDebug(@"Could not create jobTempDirPath.");
        return completion(NO);
    }

    self.backupIO = [[OWSBackupIO alloc] initWithJobTempDirPath:self.jobTempDirPath];

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
            OWSLogError(@"could not verify account status: %@.", error);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO);
            });
        }];
}

- (void)fetchAllRecordsWithCompletion:(OWSBackupJobBoolCompletion)completion
{
    OWSAssertDebug(completion);

    if (self.isComplete) {
        return;
    }

    OWSLogVerbose(@"");

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            OWSBackupExportJob *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (strongSelf.isComplete) {
                return;
            }
            strongSelf.lastValidRecordNames = [NSSet setWithArray:recordNames];
            completion(YES);
        });
    }
        failure:^(NSError *error) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO);
            });
        }];
}

- (BOOL)exportDatabase
{
    OWSAssertDebug(self.backupIO);

    OWSLogVerbose(@"");

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_DATABASE_EXPORT",
                                            @"Indicates that the database data is being exported.")
                               progress:nil];

    YapDatabaseConnection *_Nullable dbConnection = self.primaryStorage.newDatabaseConnection;
    if (!dbConnection) {
        OWSFailDebug(@"Could not create dbConnection.");
        return NO;
    }

    OWSDBExportStream *exportStream = [[OWSDBExportStream alloc] initWithBackupIO:self.backupIO];

    __block BOOL aborted = NO;
    typedef BOOL (^EntityFilter)(id object);
    typedef NSUInteger (^ExportBlock)(YapDatabaseReadTransaction *,
        NSString *,
        Class,
        EntityFilter _Nullable,
        SignalIOSProtoBackupSnapshotBackupEntityType);
    ExportBlock exportEntities = ^(YapDatabaseReadTransaction *transaction,
        NSString *collection,
        Class expectedClass,
        EntityFilter _Nullable filter,
        SignalIOSProtoBackupSnapshotBackupEntityType entityType) {
        __block NSUInteger count = 0;
        [transaction
            enumerateKeysAndObjectsInCollection:collection
                                     usingBlock:^(NSString *key, id object, BOOL *stop) {
                                         if (self.isComplete) {
                                             *stop = YES;
                                             return;
                                         }
                                         if (filter && !filter(object)) {
                                             return;
                                         }
                                         if (![object isKindOfClass:expectedClass]) {
                                             OWSFailDebug(@"unexpected class: %@", [object class]);
                                             return;
                                         }
                                         TSYapDatabaseObject *entity = object;
                                         count++;

                                         if (![exportStream writeObject:entity entityType:entityType]) {
                                             *stop = YES;
                                             aborted = YES;
                                             return;
                                         }
                                     }];
        return count;
    };

    __block NSUInteger copiedThreads = 0;
    __block NSUInteger copiedInteractions = 0;
    __block NSUInteger copiedAttachments = 0;
    __block NSUInteger copiedMigrations = 0;
    self.unsavedAttachmentExports = [NSMutableArray new];
    [dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        copiedThreads = exportEntities(transaction,
            [TSThread collection],
            [TSThread class],
            nil,
            SignalIOSProtoBackupSnapshotBackupEntityTypeThread);
        if (aborted) {
            return;
        }

        copiedAttachments = exportEntities(transaction,
            [TSAttachment collection],
            [TSAttachment class],
            ^(id object) {
                if (![object isKindOfClass:[TSAttachmentStream class]]) {
                    return NO;
                }
                TSAttachmentStream *attachmentStream = object;
                NSString *_Nullable filePath = attachmentStream.originalFilePath;
                if (!filePath) {
                    OWSLogError(@"attachment is missing file.");
                    return NO;
                    OWSAssertDebug(attachmentStream.uniqueId.length > 0);
                }

                // OWSAttachmentExport is used to lazily write an encrypted copy of the
                // attachment to disk.
                OWSAttachmentExport *attachmentExport =
                    [[OWSAttachmentExport alloc] initWithBackupIO:self.backupIO
                                                     attachmentId:attachmentStream.uniqueId
                                               attachmentFilePath:filePath];
                [self.unsavedAttachmentExports addObject:attachmentExport];

                return YES;
            },
            SignalIOSProtoBackupSnapshotBackupEntityTypeAttachment);
        if (aborted) {
            return;
        }

        // Interactions refer to threads and attachments, so copy after them.
        copiedInteractions = exportEntities(transaction,
            [TSInteraction collection],
            [TSInteraction class],
            ^(id object) {
                // Ignore disappearing messages.
                if ([object isKindOfClass:[TSMessage class]]) {
                    TSMessage *message = object;
                    if (message.isExpiringMessage) {
                        return NO;
                    }
                }
                TSInteraction *interaction = object;
                // Ignore dynamic interactions.
                if (interaction.isDynamicInteraction) {
                    return NO;
                }
                return YES;
            },
            SignalIOSProtoBackupSnapshotBackupEntityTypeInteraction);
        if (aborted) {
            return;
        }

        copiedMigrations = exportEntities(transaction,
            [OWSDatabaseMigration collection],
            [OWSDatabaseMigration class],
            nil,
            SignalIOSProtoBackupSnapshotBackupEntityTypeMigration);
    }];

    if (aborted || self.isComplete) {
        return NO;
    }

    @autoreleasepool {
        if (![exportStream flush]) {
            OWSFailDebug(@"Could not flush database snapshots.");
            return NO;
        }
    }

    self.unsavedDatabaseItems = [exportStream.exportItems mutableCopy];

    // TODO: Should we do a database checkpoint?

    OWSLogInfo(@"copiedThreads: %zd", copiedThreads);
    OWSLogInfo(@"copiedMessages: %zd", copiedInteractions);
    OWSLogInfo(@"copiedAttachments: %zd", copiedAttachments);
    OWSLogInfo(@"copiedMigrations: %zd", copiedMigrations);
    OWSLogInfo(@"copiedEntities: %zd", exportStream.totalItemCount);

    return YES;
}

- (void)saveToCloudWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    OWSLogVerbose(@"");

    self.savedDatabaseItems = [NSMutableArray new];
    self.savedAttachmentItems = [NSMutableArray new];

    unsigned long long totalFileSize = 0;
    NSUInteger totalFileCount = 0;
    {
        unsigned long long databaseFileSize = 0;
        for (OWSBackupExportItem *item in self.unsavedDatabaseItems) {
            unsigned long long fileSize =
                [OWSFileSystem fileSizeOfPath:item.encryptedItem.filePath].unsignedLongLongValue;
            ows_add_overflow(databaseFileSize, fileSize, &databaseFileSize);
        }
        OWSLogInfo(@"exporting %@: count: %zd, bytes: %llu.",
            @"database items",
            self.unsavedDatabaseItems.count,
            databaseFileSize);
        ows_add_overflow(totalFileSize, databaseFileSize, &totalFileSize);
        ows_add_overflow(totalFileCount, self.unsavedDatabaseItems.count, &totalFileCount);
    }
    {
        unsigned long long attachmentFileSize = 0;
        for (OWSAttachmentExport *attachmentExport in self.unsavedAttachmentExports) {
            unsigned long long fileSize =
                [OWSFileSystem fileSizeOfPath:attachmentExport.attachmentFilePath].unsignedLongLongValue;
            ows_add_overflow(attachmentFileSize, fileSize, &attachmentFileSize);
        }
        OWSLogInfo(@"exporting %@: count: %zd, bytes: %llu.",
            @"attachment items",
            self.unsavedAttachmentExports.count,
            attachmentFileSize);
        ows_add_overflow(totalFileSize, attachmentFileSize, &totalFileSize);
        ows_add_overflow(totalFileCount, self.unsavedAttachmentExports.count, &totalFileSize);
    }
    OWSLogInfo(@"exporting %@: count: %zd, bytes: %llu.", @"all items", totalFileCount, totalFileSize);

    [self saveNextFileToCloudWithCompletion:completion];
}

// This method uploads one file (the "next" file) each time it
// is called.  Each successful file upload re-invokes this method
// until the last (the manifest file).
- (void)saveNextFileToCloudWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    if (self.isComplete) {
        return;
    }

    // Add one for the manifest
    NSUInteger unsavedCount = (self.unsavedDatabaseItems.count + self.unsavedAttachmentExports.count + 1);
    NSUInteger savedCount = (self.savedDatabaseItems.count + self.savedAttachmentItems.count);

    CGFloat progress = (savedCount / (CGFloat)(unsavedCount + savedCount));
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_UPLOAD",
                                            @"Indicates that the backup export data is being uploaded.")
                               progress:@(progress)];

    if ([self saveNextDatabaseFileToCloudWithCompletion:completion]) {
        return;
    }
    if ([self saveNextAttachmentFileToCloudWithCompletion:completion]) {
        return;
    }
    [self saveManifestFileToCloudWithCompletion:completion];
}

// This method returns YES IFF "work was done and there might be more work to do".
- (BOOL)saveNextDatabaseFileToCloudWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.unsavedDatabaseItems.count < 1) {
        return NO;
    }

    // Pop next item from queue, preserving ordering.
    OWSBackupExportItem *item = self.unsavedDatabaseItems.firstObject;
    [self.unsavedDatabaseItems removeObjectAtIndex:0];

    OWSAssertDebug(item.encryptedItem.filePath.length > 0);

    [OWSBackupAPI saveEphemeralDatabaseFileToCloudWithFileUrl:[NSURL fileURLWithPath:item.encryptedItem.filePath]
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                item.recordName = recordName;
                [weakSelf.savedDatabaseItems addObject:item];
                [weakSelf saveNextFileToCloudWithCompletion:completion];
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Database files are critical so any error uploading them is unrecoverable.
                OWSLogVerbose(@"error while saving file: %@", item.encryptedItem.filePath);
                completion(error);
            });
        }];
    return YES;
}

// This method returns YES IFF "work was done and there might be more work to do".
- (BOOL)saveNextAttachmentFileToCloudWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.unsavedAttachmentExports.count < 1) {
        return NO;
    }

    // No need to preserve ordering of attachments.
    OWSAttachmentExport *attachmentExport = self.unsavedAttachmentExports.lastObject;
    [self.unsavedAttachmentExports removeLastObject];

    if (self.lastValidRecordNames) {
        // Wherever possible, we do incremental backups and re-use fragments of the last
        // backup and/or restore.
        // Recycling fragments doesn't just reduce redundant network activity,
        // it allows us to skip the local export work, i.e. encryption.
        // To do so, we must preserve the metadata for these fragments.
        //
        // We check two things:
        //
        // * That we already know the metadata for this fragment (from a previous backup
        //   or restore).
        // * That this record does in fact exist in our CloudKit database.
        NSString *lastRecordName = [OWSBackupAPI recordNameForPersistentFileWithFileId:attachmentExport.attachmentId];
        OWSBackupFragment *_Nullable lastBackupFragment = [OWSBackupFragment fetchObjectWithUniqueID:lastRecordName];
        if (lastBackupFragment && [self.lastValidRecordNames containsObject:lastRecordName]) {
            OWSAssertDebug(lastBackupFragment.encryptionKey.length > 0);
            OWSAssertDebug(lastBackupFragment.relativeFilePath.length > 0);

            // Recycle the metadata from the last backup's manifest.
            OWSBackupEncryptedItem *encryptedItem = [OWSBackupEncryptedItem new];
            encryptedItem.encryptionKey = lastBackupFragment.encryptionKey;
            attachmentExport.encryptedItem = encryptedItem;
            attachmentExport.relativeFilePath = lastBackupFragment.relativeFilePath;

            OWSBackupExportItem *exportItem = [OWSBackupExportItem new];
            exportItem.encryptedItem = attachmentExport.encryptedItem;
            exportItem.recordName = lastRecordName;
            exportItem.attachmentExport = attachmentExport;
            [self.savedAttachmentItems addObject:exportItem];

            OWSLogVerbose(@"recycled attachment: %@ as %@",
                attachmentExport.attachmentFilePath,
                attachmentExport.relativeFilePath);
            [self saveNextFileToCloudWithCompletion:completion];
            return YES;
        }
    }

    @autoreleasepool {
        // OWSAttachmentExport is used to lazily write an encrypted copy of the
        // attachment to disk.
        if (![attachmentExport prepareForUpload]) {
            // Attachment files are non-critical so any error uploading them is recoverable.
            [weakSelf saveNextFileToCloudWithCompletion:completion];
            return YES;
        }
        OWSAssertDebug(attachmentExport.relativeFilePath.length > 0);
        OWSAssertDebug(attachmentExport.encryptedItem);
    }

    [OWSBackupAPI savePersistentFileOnceToCloudWithFileId:attachmentExport.attachmentId
        fileUrlBlock:^{
            if (attachmentExport.encryptedItem.filePath.length < 1) {
                OWSLogError(@"attachment export missing temp file path");
                return (NSURL *)nil;
            }
            if (attachmentExport.relativeFilePath.length < 1) {
                OWSLogError(@"attachment export missing relative file path");
                return (NSURL *)nil;
            }
            return [NSURL fileURLWithPath:attachmentExport.encryptedItem.filePath];
        }
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSBackupExportJob *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (![attachmentExport cleanUp]) {
                    OWSLogError(@"couldn't clean up attachment export.");
                    // Attachment files are non-critical so any error uploading them is recoverable.
                }

                OWSBackupExportItem *exportItem = [OWSBackupExportItem new];
                exportItem.encryptedItem = attachmentExport.encryptedItem;
                exportItem.recordName = recordName;
                exportItem.attachmentExport = attachmentExport;
                [strongSelf.savedAttachmentItems addObject:exportItem];

                // Immediately save the record metadata to facilitate export resume.
                OWSBackupFragment *backupFragment = [OWSBackupFragment new];
                backupFragment.recordName = recordName;
                backupFragment.encryptionKey = exportItem.encryptedItem.encryptionKey;
                backupFragment.relativeFilePath = attachmentExport.relativeFilePath;
                backupFragment.attachmentId = attachmentExport.attachmentId;
                backupFragment.uncompressedDataLength = exportItem.uncompressedDataLength;
                [backupFragment save];

                OWSLogVerbose(@"saved attachment: %@ as %@",
                    attachmentExport.attachmentFilePath,
                    attachmentExport.relativeFilePath);
                [strongSelf saveNextFileToCloudWithCompletion:completion];
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (![attachmentExport cleanUp]) {
                    OWSLogError(@"couldn't clean up attachment export.");
                    // Attachment files are non-critical so any error uploading them is recoverable.
                }

                // Attachment files are non-critical so any error uploading them is recoverable.
                [weakSelf saveNextFileToCloudWithCompletion:completion];
            });
        }];

    return YES;
}

- (void)saveManifestFileToCloudWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self writeManifestFile];
    if (!encryptedItem) {
        completion(OWSErrorWithCodeDescription(OWSErrorCodeExportBackupFailed,
            NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                @"Error indicating the backup export could not export the user's data.")));
        return;
    }

    OWSBackupExportItem *exportItem = [OWSBackupExportItem new];
    exportItem.encryptedItem = encryptedItem;

    __weak OWSBackupExportJob *weakSelf = self;

    [OWSBackupAPI upsertManifestFileToCloudWithFileUrl:[NSURL fileURLWithPath:encryptedItem.filePath]
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSBackupExportJob *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                exportItem.recordName = recordName;
                strongSelf.manifestItem = exportItem;

                // All files have been saved to the cloud.
                completion(nil);
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // The manifest file is critical so any error uploading them is unrecoverable.
                completion(error);
            });
        }];
}

- (nullable OWSBackupEncryptedItem *)writeManifestFile
{
    OWSAssertDebug(self.savedDatabaseItems.count > 0);
    OWSAssertDebug(self.savedAttachmentItems);
    OWSAssertDebug(self.jobTempDirPath.length > 0);
    OWSAssertDebug(self.backupIO);

    NSDictionary *json = @{
        kOWSBackup_ManifestKey_DatabaseFiles : [self jsonForItems:self.savedDatabaseItems],
        kOWSBackup_ManifestKey_AttachmentFiles : [self jsonForItems:self.savedAttachmentItems],
    };

    OWSLogVerbose(@"json: %@", json);

    NSError *error;
    NSData *_Nullable jsonData =
        [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        OWSFailDebug(@"error encoding manifest file: %@", error);
        return nil;
    }
    return [self.backupIO encryptDataAsTempFile:jsonData encryptionKey:self.delegate.backupEncryptionKey];
}

- (NSArray<NSDictionary<NSString *, id> *> *)jsonForItems:(NSArray<OWSBackupExportItem *> *)items
{
    NSMutableArray *result = [NSMutableArray new];
    for (OWSBackupExportItem *item in items) {
        NSMutableDictionary<NSString *, id> *itemJson = [NSMutableDictionary new];
        OWSAssertDebug(item.recordName.length > 0);

        itemJson[kOWSBackup_ManifestKey_RecordName] = item.recordName;
        OWSAssertDebug(item.encryptedItem.encryptionKey.length > 0);
        itemJson[kOWSBackup_ManifestKey_EncryptionKey] = item.encryptedItem.encryptionKey.base64EncodedString;
        if (item.attachmentExport) {
            OWSAssertDebug(item.attachmentExport.relativeFilePath.length > 0);
            itemJson[kOWSBackup_ManifestKey_RelativeFilePath] = item.attachmentExport.relativeFilePath;
        }
        if (item.attachmentExport.attachmentId) {
            OWSAssertDebug(item.attachmentExport.attachmentId.length > 0);
            itemJson[kOWSBackup_ManifestKey_AttachmentId] = item.attachmentExport.attachmentId;
        }
        if (item.uncompressedDataLength) {
            itemJson[kOWSBackup_ManifestKey_DataSize] = item.uncompressedDataLength;
        }
        [result addObject:itemJson];
    }

    return result;
}

- (void)cleanUpWithCompletion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(completion);

    if (self.isComplete) {
        // Job was aborted.
        return completion(nil);
    }

    OWSLogVerbose(@"");

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CLEAN_UP",
                                            @"Indicates that the cloud is being cleaned up.")
                               progress:nil];

    // Now that our backup export has successfully completed,
    // we try to clean up the cloud.  We can safely delete any
    // records not involved in this backup export.
    NSMutableSet<NSString *> *activeRecordNames = [NSMutableSet new];

    OWSAssertDebug(self.savedDatabaseItems.count > 0);
    for (OWSBackupExportItem *item in self.savedDatabaseItems) {
        OWSAssertDebug(item.recordName.length > 0);
        OWSAssertDebug(![activeRecordNames containsObject:item.recordName]);
        [activeRecordNames addObject:item.recordName];
    }
    for (OWSBackupExportItem *item in self.savedAttachmentItems) {
        OWSAssertDebug(item.recordName.length > 0);
        OWSAssertDebug(![activeRecordNames containsObject:item.recordName]);
        [activeRecordNames addObject:item.recordName];
    }
    OWSAssertDebug(self.manifestItem.recordName.length > 0);
    OWSAssertDebug(![activeRecordNames containsObject:self.manifestItem.recordName]);
    [activeRecordNames addObject:self.manifestItem.recordName];

    // Because we do "lazy attachment restores", we need to include the record names for all
    // records that haven't been restored yet.
    NSArray<NSString *> *restoringRecordNames = [OWSBackup.sharedManager attachmentRecordNamesForLazyRestore];
    [activeRecordNames addObjectsFromArray:restoringRecordNames];

    [self cleanUpMetadataCacheWithActiveRecordNames:activeRecordNames];

    [self cleanUpCloudWithActiveRecordNames:activeRecordNames completion:completion];
}

- (void)cleanUpMetadataCacheWithActiveRecordNames:(NSSet<NSString *> *)activeRecordNames
{
    OWSAssertDebug(activeRecordNames.count > 0);

    if (self.isComplete) {
        // Job was aborted.
        return;
    }

    // After every successful backup export, we can (and should) cull metadata
    // for any backup fragment (i.e. CloudKit record) that wasn't involved in
    // the latest backup export.
    [self.primaryStorage.newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
        [obsoleteRecordNames addObjectsFromArray:[transaction allKeysInCollection:[OWSBackupFragment collection]]];
        [obsoleteRecordNames minusSet:activeRecordNames];

        [transaction removeObjectsForKeys:obsoleteRecordNames.allObjects inCollection:[OWSBackupFragment collection]];
    }];
}

- (void)cleanUpCloudWithActiveRecordNames:(NSSet<NSString *> *)activeRecordNames
                               completion:(OWSBackupJobCompletion)completion
{
    OWSAssertDebug(activeRecordNames.count > 0);
    OWSAssertDebug(completion);

    if (self.isComplete) {
        // Job was aborted.
        return completion(nil);
    }

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI fetchAllRecordNamesWithSuccess:^(NSArray<NSString *> *recordNames) {
        // Ensure that we continue to work off the main thread.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
            [obsoleteRecordNames addObjectsFromArray:recordNames];
            [obsoleteRecordNames minusSet:activeRecordNames];

            OWSLogVerbose(@"recordNames: %zd - activeRecordNames: %zd = obsoleteRecordNames: %zd",
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
    OWSAssertDebug(obsoleteRecordNames);
    OWSAssertDebug(completion);

    OWSLogVerbose(@"");

    if (obsoleteRecordNames.count < 1) {
        // No more records to delete; cleanup is complete.
        return completion(nil);
    }

    if (self.isComplete) {
        // Job was aborted.
        return completion(nil);
    }

    CGFloat progress = (obsoleteRecordNames.count / (CGFloat)(obsoleteRecordNames.count + deletedCount));
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CLEAN_UP",
                                            @"Indicates that the cloud is being cleaned up.")
                               progress:@(progress)];

    static const NSUInteger kMaxBatchSize = 100;
    NSMutableArray<NSString *> *batchRecordNames = [NSMutableArray new];
    while (obsoleteRecordNames.count > 0 && batchRecordNames.count < kMaxBatchSize) {
        NSString *recordName = obsoleteRecordNames.lastObject;
        [obsoleteRecordNames removeLastObject];
        [batchRecordNames addObject:recordName];
    }

    __weak OWSBackupExportJob *weakSelf = self;
    [OWSBackupAPI deleteRecordsFromCloudWithRecordNames:batchRecordNames
        success:^{
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
                                    deletedCount:deletedCount + batchRecordNames.count
                                      completion:completion];
            });
        }
        failure:^(NSError *error) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Cloud cleanup is non-critical so any error is recoverable.
                [weakSelf deleteRecordsFromCloud:obsoleteRecordNames
                                    deletedCount:deletedCount + batchRecordNames.count
                                      completion:completion];
            });
        }];
}

@end

NS_ASSUME_NONNULL_END
