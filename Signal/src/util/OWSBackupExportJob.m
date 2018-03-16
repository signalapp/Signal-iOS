//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExportJob.h"
#import "OWSBackupEncryption.h"
#import "OWSDatabaseMigration.h"
#import "OWSSignalServiceProtos.pb.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/NSData+Base64.h>
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

// This property is optional and represents the location of this
// item relative to the root directory for items of this type.
//@property (nonatomic, nullable) NSString *fileRelativePath;

// This property is optional and is only used for attachments.
@property (nonatomic, nullable) OWSAttachmentExport *attachmentExport;

// This property is optional.
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

    OWSAssert(encryptedItem);

    self.encryptedItem = encryptedItem;

    return self;
}

@end

#pragma mark -

@interface OWSDBExportStream : NSObject

@property (nonatomic) OWSBackupEncryption *encryption;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *exportItems;

@property (nonatomic, nullable) OWSSignalServiceProtosBackupSnapshotBuilder *backupSnapshotBuilder;

@property (nonatomic) NSUInteger cachedItemCount;

@property (nonatomic) NSUInteger totalItemCount;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSDBExportStream

- (instancetype)initWithEncryption:(OWSBackupEncryption *)encryption
{
    if (!(self = [super init])) {
        return self;
    }

    OWSAssert(encryption);

    self.exportItems = [NSMutableArray new];
    self.encryption = encryption;

    return self;
}

- (BOOL)writeObject:(TSYapDatabaseObject *)object
         entityType:(OWSSignalServiceProtosBackupSnapshotBackupEntityType)entityType
{
    OWSAssert(object);

    NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:object];
    if (!data) {
        OWSProdLogAndFail(@"%@ couldn't serialize database object: %@", self.logTag, [object class]);
        return NO;
    }

    if (!self.backupSnapshotBuilder) {
        self.backupSnapshotBuilder = [OWSSignalServiceProtosBackupSnapshotBuilder new];
    }

    OWSSignalServiceProtosBackupSnapshotBackupEntityBuilder *entityBuilder =
        [OWSSignalServiceProtosBackupSnapshotBackupEntityBuilder new];
    [entityBuilder setType:entityType];
    [entityBuilder setEntityData:data];

    [self.backupSnapshotBuilder addEntity:[entityBuilder build]];

    self.cachedItemCount = self.cachedItemCount + 1;
    self.totalItemCount = self.totalItemCount + 1;

    static const int kMaxDBSnapshotSize = 1000;
    if (self.cachedItemCount > kMaxDBSnapshotSize) {
        return [self flush];
    }

    return YES;
}

// Write cached data to disk, if necessary.
- (BOOL)flush
{
    if (!self.backupSnapshotBuilder) {
        return YES;
    }

    NSData *_Nullable uncompressedData = [self.backupSnapshotBuilder build].data;
    NSUInteger uncompressedDataLength = uncompressedData.length;
    self.backupSnapshotBuilder = nil;
    self.cachedItemCount = 0;
    if (!uncompressedData) {
        OWSProdLogAndFail(@"%@ couldn't convert database snapshot to data.", self.logTag);
        return NO;
    }

    NSData *compressedData = [self.encryption compressData:uncompressedData];

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self.encryption encryptDataAsTempFile:compressedData];
    if (!encryptedItem) {
        OWSProdLogAndFail(@"%@ couldn't encrypt database snapshot.", self.logTag);
        return NO;
    }

    OWSBackupExportItem *exportItem = [[OWSBackupExportItem alloc] initWithEncryptedItem:encryptedItem];
    exportItem.uncompressedDataLength = @(uncompressedDataLength);
    [self.exportItems addObject:exportItem];

    return YES;
}

@end

#pragma mark -

@interface OWSAttachmentExport : NSObject

@property (nonatomic) OWSBackupEncryption *encryption;
@property (nonatomic) NSString *attachmentId;
@property (nonatomic) NSString *attachmentFilePath;
@property (nonatomic, nullable) NSString *relativeFilePath;
@property (nonatomic) OWSBackupEncryptedItem *encryptedItem;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation OWSAttachmentExport

- (instancetype)initWithEncryption:(OWSBackupEncryption *)encryption
                      attachmentId:(NSString *)attachmentId
                attachmentFilePath:(NSString *)attachmentFilePath
{
    if (!(self = [super init])) {
        return self;
    }

    OWSAssert(encryption);
    OWSAssert(attachmentId.length > 0);
    OWSAssert(attachmentFilePath.length > 0);

    self.encryption = encryption;
    self.attachmentId = attachmentId;
    self.attachmentFilePath = attachmentFilePath;

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    DDLogVerbose(@"Dealloc: %@", self.class);
}

// On success, encryptedItem will be non-nil.
- (BOOL)prepareForUpload
{
    OWSAssert(self.attachmentId.length > 0);
    OWSAssert(self.attachmentFilePath.length > 0);

    NSString *attachmentsDirPath = [TSAttachmentStream attachmentsFolder];
    if (![self.attachmentFilePath hasPrefix:attachmentsDirPath]) {
        DDLogError(@"%@ attachment has unexpected path.", self.logTag);
        OWSFail(@"%@ attachment has unexpected path: %@", self.logTag, self.attachmentFilePath);
        return NO;
    }
    NSString *relativeFilePath = [self.attachmentFilePath substringFromIndex:attachmentsDirPath.length];
    NSString *pathSeparator = @"/";
    if ([relativeFilePath hasPrefix:pathSeparator]) {
        relativeFilePath = [relativeFilePath substringFromIndex:pathSeparator.length];
    }
    self.relativeFilePath = relativeFilePath;

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self.encryption encryptFileAsTempFile:self.attachmentFilePath];
    if (!encryptedItem) {
        DDLogError(@"%@ attachment could not be encrypted.", self.logTag);
        OWSFail(@"%@ attachment could not be encrypted: %@", self.logTag, self.attachmentFilePath);
        return NO;
    }
    self.encryptedItem = encryptedItem;
    return YES;
}

@end

#pragma mark -

@interface OWSBackupExportJob ()

@property (nonatomic, nullable) OWSBackgroundTask *backgroundTask;

@property (nonatomic) OWSBackupEncryption *encryption;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *unsavedDatabaseItems;

@property (nonatomic) NSMutableArray<OWSAttachmentExport *> *unsavedAttachmentExports;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *savedDatabaseItems;

@property (nonatomic) NSMutableArray<OWSBackupExportItem *> *savedAttachmentItems;

@property (nonatomic, nullable) OWSBackupExportItem *manifestItem;

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

    self.encryption = [[OWSBackupEncryption alloc] initWithJobTempDirPath:self.jobTempDirPath];

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

- (BOOL)exportDatabase
{
    OWSAssert(self.encryption);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_DATABASE_EXPORT",
                                            @"Indicates that the database data is being exported.")
                               progress:nil];

    YapDatabaseConnection *_Nullable dbConnection = self.primaryStorage.newDatabaseConnection;
    if (!dbConnection) {
        OWSProdLogAndFail(@"%@ Could not create dbConnection.", self.logTag);
        return NO;
    }

    OWSDBExportStream *exportStream = [[OWSDBExportStream alloc] initWithEncryption:self.encryption];

    __block BOOL aborted = NO;
    typedef BOOL (^EntityFilter)(id object);
    typedef NSUInteger (^ExportBlock)(YapDatabaseReadTransaction *,
        NSString *,
        Class,
        EntityFilter _Nullable,
        OWSSignalServiceProtosBackupSnapshotBackupEntityType);
    ExportBlock exportEntities = ^(YapDatabaseReadTransaction *transaction,
        NSString *collection,
        Class expectedClass,
        EntityFilter _Nullable filter,
        OWSSignalServiceProtosBackupSnapshotBackupEntityType entityType) {
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
                                             OWSProdLogAndFail(@"%@ unexpected class: %@", self.logTag, [object class]);
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
            OWSSignalServiceProtosBackupSnapshotBackupEntityTypeThread);
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
                NSString *_Nullable filePath = attachmentStream.filePath;
                if (!filePath) {
                    DDLogError(@"%@ attachment is missing file.", self.logTag);
                    return NO;
                    OWSAssert(attachmentStream.uniqueId.length > 0);
                }

                // OWSAttachmentExport is used to lazily write an encrypted copy of the
                // attachment to disk.
                OWSAttachmentExport *attachmentExport =
                    [[OWSAttachmentExport alloc] initWithEncryption:self.encryption
                                                       attachmentId:attachmentStream.uniqueId
                                                 attachmentFilePath:filePath];
                [self.unsavedAttachmentExports addObject:attachmentExport];

                return YES;
            },
            OWSSignalServiceProtosBackupSnapshotBackupEntityTypeAttachment);
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
            OWSSignalServiceProtosBackupSnapshotBackupEntityTypeInteraction);
        if (aborted) {
            return;
        }

        copiedMigrations = exportEntities(transaction,
            [OWSDatabaseMigration collection],
            [OWSDatabaseMigration class],
            nil,
            OWSSignalServiceProtosBackupSnapshotBackupEntityTypeMigration);
    }];

    if (aborted || self.isComplete) {
        return NO;
    }

    if (![exportStream flush]) {
        OWSProdLogAndFail(@"%@ Could not flush database snapshots.", self.logTag);
        return NO;
    }

    self.unsavedDatabaseItems = [exportStream.exportItems mutableCopy];

    // TODO: Should we do a database checkpoint?

    DDLogInfo(@"%@ copiedThreads: %zd", self.logTag, copiedThreads);
    DDLogInfo(@"%@ copiedMessages: %zd", self.logTag, copiedInteractions);
    DDLogInfo(@"%@ copiedAttachments: %zd", self.logTag, copiedAttachments);
    DDLogInfo(@"%@ copiedMigrations: %zd", self.logTag, copiedMigrations);
    DDLogInfo(@"%@ copiedEntities: %zd", self.logTag, exportStream.totalItemCount);

    return YES;
}

- (void)saveToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.savedDatabaseItems = [NSMutableArray new];
    self.savedAttachmentItems = [NSMutableArray new];

    {
        unsigned long long totalFileSize = 0;
        for (OWSBackupExportItem *item in self.unsavedDatabaseItems) {
            totalFileSize += [OWSFileSystem fileSizeOfPath:item.encryptedItem.filePath].unsignedLongLongValue;
        }
        DDLogInfo(@"%@ exporting %@: count: %zd, bytes: %llu.",
            self.logTag,
            @"database items",
            self.unsavedDatabaseItems.count,
            totalFileSize);
    }
    {
        unsigned long long totalFileSize = 0;
        for (OWSAttachmentExport *attachmentExport in self.unsavedAttachmentExports) {
            totalFileSize += [OWSFileSystem fileSizeOfPath:attachmentExport.attachmentFilePath].unsignedLongLongValue;
        }
        DDLogInfo(@"%@ exporting %@: count: %zd, bytes: %llu.",
            self.logTag,
            @"attachment items",
            self.unsavedAttachmentExports.count,
            totalFileSize);
    }

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

    // Add one for the manifest
    NSUInteger unsavedCount = (self.unsavedDatabaseItems.count + self.unsavedAttachmentExports.count + 1);
    NSUInteger savedCount = (self.savedDatabaseItems.count + self.savedAttachmentItems.count);

    CGFloat progress = (savedCount / (CGFloat)(unsavedCount + savedCount));
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

// This method returns YES IFF "work was done and there might be more work to do".
- (BOOL)saveNextDatabaseFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.unsavedDatabaseItems.count < 1) {
        return NO;
    }

    // Pop next item from queue, preserving ordering.
    OWSBackupExportItem *item = self.unsavedDatabaseItems.firstObject;
    [self.unsavedDatabaseItems removeObjectAtIndex:0];

    OWSAssert(item.encryptedItem.filePath.length > 0);

    [OWSBackupAPI saveEphemeralDatabaseFileToCloudWithFileUrl:[NSURL fileURLWithPath:item.encryptedItem.filePath]
        success:^(NSString *recordName) {
            // Ensure that we continue to work off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                item.recordName = recordName;
                [weakSelf.savedDatabaseItems addObject:item];
                [weakSelf saveNextFileToCloud:completion];
            });
        }
        failure:^(NSError *error) {
            // Database files are critical so any error uploading them is unrecoverable.
            DDLogVerbose(@"%@ error while saving file: %@", weakSelf.logTag, item.encryptedItem.filePath);
            completion(error);
        }];
    return YES;
}

// This method returns YES IFF "work was done and there might be more work to do".
- (BOOL)saveNextAttachmentFileToCloud:(OWSBackupJobCompletion)completion
{
    OWSAssert(completion);

    __weak OWSBackupExportJob *weakSelf = self;
    if (self.unsavedAttachmentExports.count < 1) {
        return NO;
    }

    // No need to preserve ordering of attachments.
    OWSAttachmentExport *attachmentExport = self.unsavedAttachmentExports.lastObject;
    [self.unsavedAttachmentExports removeLastObject];

    // OWSAttachmentExport is used to lazily write an encrypted copy of the
    // attachment to disk.
    if (![attachmentExport prepareForUpload]) {
        // Attachment files are non-critical so any error uploading them is recoverable.
        [weakSelf saveNextFileToCloud:completion];
        return YES;
    }
    OWSAssert(attachmentExport.relativeFilePath.length > 0);
    OWSAssert(attachmentExport.encryptedItem);

    [OWSBackupAPI savePersistentFileOnceToCloudWithFileId:attachmentExport.attachmentId
        fileUrlBlock:^{
            if (attachmentExport.encryptedItem.filePath.length < 1) {
                DDLogError(@"%@ attachment export missing temp file path", self.logTag);
                return (NSURL *)nil;
            }
            if (attachmentExport.relativeFilePath.length < 1) {
                DDLogError(@"%@ attachment export missing relative file path", self.logTag);
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

                OWSBackupExportItem *exportItem = [OWSBackupExportItem new];
                exportItem.encryptedItem = attachmentExport.encryptedItem;
                exportItem.recordName = recordName;
                exportItem.attachmentExport = attachmentExport;
                [strongSelf.savedAttachmentItems addObject:exportItem];

                DDLogVerbose(@"%@ saved attachment: %@ as %@",
                    self.logTag,
                    attachmentExport.attachmentFilePath,
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

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self writeManifestFile];
    if (!encryptedItem) {
        completion(OWSErrorWithCodeDescription(OWSErrorCodeExportBackupFailed,
            NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                @"Error indicating the a backup export could not export the user's data.")));
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
            // The manifest file is critical so any error uploading them is unrecoverable.
            completion(error);
        }];
}

- (nullable OWSBackupEncryptedItem *)writeManifestFile
{
    OWSAssert(self.savedDatabaseItems.count > 0);
    OWSAssert(self.savedAttachmentItems);
    OWSAssert(self.jobTempDirPath.length > 0);
    OWSAssert(self.encryption);

    NSDictionary *json = @{
        kOWSBackup_ManifestKey_DatabaseFiles : [self jsonForItems:self.savedDatabaseItems],
        kOWSBackup_ManifestKey_AttachmentFiles : [self jsonForItems:self.savedAttachmentItems],
    };

    DDLogVerbose(@"%@ json: %@", self.logTag, json);

    NSError *error;
    NSData *_Nullable jsonData =
        [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        OWSProdLogAndFail(@"%@ error encoding manifest file: %@", self.logTag, error);
        return nil;
    }
    return [self.encryption encryptDataAsTempFile:jsonData encryptionKey:self.delegate.backupEncryptionKey];
}

- (NSArray<NSDictionary<NSString *, id> *> *)jsonForItems:(NSArray<OWSBackupExportItem *> *)items
{
    NSMutableArray *result = [NSMutableArray new];
    for (OWSBackupExportItem *item in items) {
        NSMutableDictionary<NSString *, id> *itemJson = [NSMutableDictionary new];
        OWSAssert(item.recordName.length > 0);

        itemJson[kOWSBackup_ManifestKey_RecordName] = item.recordName;
        OWSAssert(item.encryptedItem.filePath.length > 0);
        OWSAssert(item.encryptedItem.encryptionKey.length > 0);
        itemJson[kOWSBackup_ManifestKey_EncryptionKey] = item.encryptedItem.encryptionKey.base64EncodedString;
        if (item.attachmentExport) {
            OWSAssert(item.attachmentExport.relativeFilePath.length > 0);
            itemJson[kOWSBackup_ManifestKey_RelativeFilePath] = item.attachmentExport.relativeFilePath;
        }
        if (item.uncompressedDataLength) {
            itemJson[kOWSBackup_ManifestKey_DataSize] = item.uncompressedDataLength;
        }
        [result addObject:itemJson];
    }

    return result;
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

    OWSAssert(self.savedDatabaseItems.count > 0);
    for (OWSBackupExportItem *item in self.savedDatabaseItems) {
        OWSAssert(item.recordName.length > 0);
        OWSAssert(![activeRecordNames containsObject:item.recordName]);
        [activeRecordNames addObject:item.recordName];
    }
    for (OWSBackupExportItem *item in self.savedAttachmentItems) {
        OWSAssert(item.recordName.length > 0);
        OWSAssert(![activeRecordNames containsObject:item.recordName]);
        [activeRecordNames addObject:item.recordName];
    }
    OWSAssert(self.manifestItem.recordName.length > 0);
    OWSAssert(![activeRecordNames containsObject:self.manifestItem.recordName]);
    [activeRecordNames addObject:self.manifestItem.recordName];

    // TODO: If we implement "lazy restores" where attachments (etc.) are
    // restored lazily, we need to include the record names for all
    // records that haven't been restored yet.

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
