//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExportJob.h"
#import "OWSBackupIO.h"
#import "OWSDatabaseMigration.h"
#import "Signal-Swift.h"
#import <CloudKit/CloudKit.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSThread.h>

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

+ (instancetype)new NS_UNAVAILABLE;
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

+ (instancetype)new NS_UNAVAILABLE;
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
- (BOOL)writeObject:(NSObject *)object
         collection:(NSString *)collection
                key:(NSString *)key
         entityType:(SignalIOSProtoBackupSnapshotBackupEntityType)entityType
{
    OWSAssertDebug(object);
    OWSAssertDebug(collection.length > 0);
    OWSAssertDebug(key.length > 0);

    NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:object];
    if (!data) {
        OWSFailDebug(@"couldn't serialize database object: %@", [object class]);
        return NO;
    }

    if (!self.backupSnapshotBuilder) {
        self.backupSnapshotBuilder = [SignalIOSProtoBackupSnapshot builder];
    }

    SignalIOSProtoBackupSnapshotBackupEntityBuilder *entityBuilder =
        [SignalIOSProtoBackupSnapshotBackupEntity builderWithEntityData:data collection:collection key:key];
    [entityBuilder setType:entityType];

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

+ (instancetype)new NS_UNAVAILABLE;
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

@property (nonatomic, nullable) OWSBackupExportItem *localProfileAvatarItem;

@property (nonatomic, nullable) OWSBackupExportItem *manifestItem;

// If we are replacing an existing backup, we use some of its contents for continuity.
@property (nonatomic, nullable) NSSet<NSString *> *lastValidRecordNames;

@end

#pragma mark -

@implementation OWSBackupExportJob

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (OWSBackup *)backup
{
    OWSAssertDebug(AppEnvironment.shared.backup);

    return AppEnvironment.shared.backup;
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager shared];
}

#pragma mark -

- (void)start
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [self updateProgressWithDescription:nil progress:nil];

    [self.backup ensureCloudKitAccess]
        .thenInBackground(^{
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_CONFIGURATION",
                                                    @"Indicates that the backup export is being configured.")
                                       progress:nil];

            return [self configureExport];
        })
        .thenInBackground(^{
            return [self fetchAllRecords];
        })
        .thenInBackground(^{
            [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_EXPORT",
                                                    @"Indicates that the backup export data is being exported.")
                                       progress:nil];

            return [self exportDatabase];
        })
        .thenInBackground(^{
            return [self saveToCloud];
        })
        .thenInBackground(^{
            return [self cleanUp];
        })
        .thenInBackground(^{
            [self succeed];
        })
        .catch(^(NSError *error) {
            OWSFailDebug(@"Backup export failed with error: %@.", error);

            [self
                failWithErrorDescription:NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                                             @"Error indicating the backup export could not export the user's data.")];
        });
}

- (AnyPromise *)configureExport
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    if (![self ensureJobTempDir]) {
        OWSFailDebug(@"Could not create jobTempDirPath.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not create jobTempDirPath.")];
    }

    self.backupIO = [[OWSBackupIO alloc] initWithJobTempDirPath:self.jobTempDirPath];

    // We need to verify that we have a valid account.
    // Otherwise, if we re-register on another device, we
    // continue to backup on our old device, overwriting
    // backups from the new device.
    //
    // We use an arbitrary request that requires authentication
    // to verify our account state.
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        TSRequest *currentSignedPreKey = [OWSRequestFactory currentSignedPreKeyRequest];
        [[TSNetworkManager shared] makeRequest:currentSignedPreKey
            success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) { resolve(@(1)); }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                // TODO: We may want to surface this in the UI.
                OWSLogError(@"could not verify account status: %@.", error);
                resolve(error);
            }];
    }];
}

- (AnyPromise *)fetchAllRecords
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [OWSBackupAPI fetchAllRecordNamesWithRecipientId:self.recipientId
            success:^(NSArray<NSString *> *recordNames) {
                if (self.isComplete) {
                    return resolve(OWSBackupErrorWithDescription(@"Backup export no longer active."));
                }
                self.lastValidRecordNames = [NSSet setWithArray:recordNames];
                resolve(@(1));
            }
            failure:^(NSError *error) {
                resolve(error);
            }];
    }];
}

- (AnyPromise *)exportDatabase
{
    OWSAssertDebug(self.backupIO);

    OWSLogVerbose(@"");

    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        if (![self performExportDatabase]) {
            NSError *error = OWSBackupErrorWithDescription(@"Backup export failed.");
            return resolve(error);
        }
        
        resolve(@(1));
    }];
}

- (BOOL)performExportDatabase
{
    OWSAssertDebug(self.backupIO);

    OWSLogVerbose(@"");

    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_DATABASE_EXPORT",
                                            @"Indicates that the database data is being exported.")
                               progress:nil];

    OWSDBExportStream *exportStream = [[OWSDBExportStream alloc] initWithBackupIO:self.backupIO];

    __block BOOL aborted = NO;
    typedef BOOL (^EntityFilter)(id object);
    typedef NSUInteger (^ExportBlock)(YapDatabaseReadTransaction *,
        NSString *,
        Class,
        EntityFilter _Nullable,
        SignalIOSProtoBackupSnapshotBackupEntityType);

    __block NSUInteger copiedThreads = 0;
    __block NSUInteger copiedInteractions = 0;
    __block NSUInteger copiedAttachments = 0;
    __block NSUInteger copiedMisc = 0;
    self.unsavedAttachmentExports = [NSMutableArray new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [TSThread anyEnumerateWithTransaction:transaction
                                      batched:YES
                                        block:^(TSThread *object, BOOL *stop) {
                                            NSString *collection = TSThread.collection;
                                            SignalIOSProtoBackupSnapshotBackupEntityType entityType
                                                = SignalIOSProtoBackupSnapshotBackupEntityTypeThread;

                                            if (self.isComplete) {
                                                *stop = YES;
                                                return;
                                            }
                                            copiedThreads++;
                                            if (![exportStream writeObject:object
                                                                collection:collection
                                                                       key:object.uniqueId
                                                                entityType:entityType]) {
                                                *stop = YES;
                                                aborted = YES;
                                                return;
                                            }
                                        }];
        if (aborted) {
            return;
        }
        [TSAttachment
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(TSAttachment *object, BOOL *stop) {
                                      NSString *collection = TSAttachment.collection;
                                      SignalIOSProtoBackupSnapshotBackupEntityType entityType
                                          = SignalIOSProtoBackupSnapshotBackupEntityTypeAttachment;

                                      if (self.isComplete) {
                                          *stop = YES;
                                          return;
                                      }

                                      TSYapDatabaseObject *objectToWrite = object;
                                      // No need to backup the contents (e.g. the file on disk)
                                      // of attachment pointers.
                                      // After a restore, users will be able "tap to retry".
                                      if ([object isKindOfClass:[TSAttachmentStream class]]) {
                                          TSAttachmentStream *attachmentStream = (TSAttachmentStream *)object;
                                          NSString *_Nullable filePath = attachmentStream.originalFilePath;
                                          if (!filePath || ![NSFileManager.defaultManager fileExistsAtPath:filePath]) {
                                              OWSFailDebug(@"attachment is missing file.");
                                              return;
                                          }

                                          // OWSAttachmentExport is used to lazily write an encrypted copy of the
                                          // attachment to disk.
                                          OWSAttachmentExport *attachmentExport =
                                              [[OWSAttachmentExport alloc] initWithBackupIO:self.backupIO
                                                                               attachmentId:attachmentStream.uniqueId
                                                                         attachmentFilePath:filePath];
                                          [self.unsavedAttachmentExports addObject:attachmentExport];


                                          // Convert attachment streams to pointers,
                                          // since we'll need to restore them.
                                          objectToWrite = [[TSAttachmentPointer alloc]
                                              initForRestoreWithAttachmentStream:attachmentStream];
                                      }

                                      copiedAttachments++;
                                      if (![exportStream writeObject:objectToWrite
                                                          collection:collection
                                                                 key:object.uniqueId
                                                          entityType:entityType]) {
                                          *stop = YES;
                                          aborted = YES;
                                          return;
                                      }
                                  }];
        if (aborted) {
            return;
        }

        // Interactions refer to threads and attachments, so copy after them.
        [TSInteraction
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(TSInteraction *object, BOOL *stop) {
                                      NSString *collection = TSInteraction.collection;
                                      SignalIOSProtoBackupSnapshotBackupEntityType entityType
                                          = SignalIOSProtoBackupSnapshotBackupEntityTypeInteraction;

                                      if (self.isComplete) {
                                          *stop = YES;
                                          return;
                                      }

                                      // Ignore both kinds of disappearing messages.
                                      if ([object isKindOfClass:[TSMessage class]]) {
                                          TSMessage *message = (TSMessage *)object;
                                          if (message.hasPerConversationExpiration || message.isViewOnceMessage) {
                                              return;
                                          }
                                      }
                                      // Ignore dynamic interactions.
                                      if (object.isDynamicInteraction) {
                                          return;
                                      }

                                      copiedInteractions++;
                                      if (![exportStream writeObject:object
                                                          collection:collection
                                                                 key:object.uniqueId
                                                          entityType:entityType]) {
                                          *stop = YES;
                                          aborted = YES;
                                          return;
                                      }
                                  }];
        if (aborted) {
            return;
        }

        // POST GRDB TODO: After GRDB migration, backup MiscCollectionsToBackup().
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
    OWSLogInfo(@"copiedMisc: %zd", copiedMisc);
    OWSLogInfo(@"copiedEntities: %zd", exportStream.totalItemCount);

    return YES;
}

- (AnyPromise *)saveToCloud
{
    OWSLogVerbose(@"");

    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

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

    // Add one for the manifest
    NSUInteger unsavedCount = (self.unsavedDatabaseItems.count + self.unsavedAttachmentExports.count + 1);
    NSUInteger savedCount = (self.savedDatabaseItems.count + self.savedAttachmentItems.count);
    // Ignore localProfileAvatarItem for now.

    CGFloat progress = (savedCount / (CGFloat)(unsavedCount + savedCount));
    [self updateProgressWithDescription:NSLocalizedString(@"BACKUP_EXPORT_PHASE_UPLOAD",
                                            @"Indicates that the backup export data is being uploaded.")
                               progress:@(progress)];

    // Save attachment files _before_ anything else, since they
    // are the only reusable backup records.
    return [self saveAttachmentFilesToCloud]
        .thenInBackground(^{
            return [self saveDatabaseFilesToCloud];
        })
        .thenInBackground(^{
            return [self saveLocalProfileAvatarToCloud];
        })
        .thenInBackground(^{
            return [self saveManifestFileToCloud];
        });
}

// This method returns YES IFF "work was done and there might be more work to do".
- (AnyPromise *)saveDatabaseFilesToCloud
{
    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    NSArray<OWSBackupExportItem *> *items = [self.unsavedDatabaseItems copy];
    NSMutableArray<CKRecord *> *records = [NSMutableArray new];
    for (OWSBackupExportItem *item in items) {
        OWSAssertDebug(item.encryptedItem.filePath.length > 0);

        NSString *recordName =
            [OWSBackupAPI recordNameForEphemeralFileWithRecipientId:self.recipientId label:@"database"];
        CKRecord *record =
            [OWSBackupAPI recordForFileUrl:[NSURL fileURLWithPath:item.encryptedItem.filePath] recordName:recordName];
        [records addObject:record];
    }

    // TODO: Expose progress.
    return [OWSBackupAPI saveRecordsToCloudObjcWithRecords:records].thenInBackground(^{
        OWSAssertDebug(items.count == records.count);
        NSUInteger count = MIN(items.count, records.count);
        for (NSUInteger i = 0; i < count; i++) {
            OWSBackupExportItem *item = items[i];
            CKRecord *record = records[i];

            OWSAssertDebug(record.recordID.recordName.length > 0);
            item.recordName = record.recordID.recordName;
        }

        [self.savedDatabaseItems addObjectsFromArray:items];
        [self.unsavedDatabaseItems removeObjectsInArray:items];
    });
}

// This method returns YES IFF "work was done and there might be more work to do".
- (AnyPromise *)saveAttachmentFilesToCloud
{
    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    AnyPromise *promise = [AnyPromise promiseWithValue:@(1)];
    NSMutableArray<OWSAttachmentExport *> *items = [NSMutableArray new];
    NSMutableArray<CKRecord *> *records = [NSMutableArray new];

    for (OWSAttachmentExport *attachmentExport in self.unsavedAttachmentExports) {
        if ([self tryToSkipAttachmentUpload:attachmentExport]) {
            continue;
        }

        promise = promise.thenInBackground(^{
            @autoreleasepool {
                // OWSAttachmentExport is used to lazily write an encrypted copy of the
                // attachment to disk.
                if (![attachmentExport prepareForUpload]) {
                    // Attachment files are non-critical so any error preparing them is recoverable.
                    return @(1);
                }
                OWSAssertDebug(attachmentExport.relativeFilePath.length > 0);
                OWSAssertDebug(attachmentExport.encryptedItem);
            }

            NSURL *_Nullable fileUrl = ^{
                if (attachmentExport.encryptedItem.filePath.length < 1) {
                    OWSLogError(@"attachment export missing temp file path");
                    return (NSURL *)nil;
                }
                if (attachmentExport.relativeFilePath.length < 1) {
                    OWSLogError(@"attachment export missing relative file path");
                    return (NSURL *)nil;
                }
                return [NSURL fileURLWithPath:attachmentExport.encryptedItem.filePath];
            }();

            if (!fileUrl) {
                // Attachment files are non-critical so any error preparing them is recoverable.
                return @(1);
            }

            NSString *recordName =
                [OWSBackupAPI recordNameForPersistentFileWithRecipientId:self.recipientId
                                                                  fileId:attachmentExport.attachmentId];
            CKRecord *record = [OWSBackupAPI recordForFileUrl:fileUrl recordName:recordName];
            [records addObject:record];
            [items addObject:attachmentExport];
            return @(1);
        });
    }

    void (^cleanup)(void) = ^{
        for (OWSAttachmentExport *attachmentExport in items) {
            if (![attachmentExport cleanUp]) {
                OWSLogError(@"couldn't clean up attachment export.");
                // Attachment files are non-critical so any error uploading them is recoverable.
            }
        }
    };

    // TODO: Expose progress.
    return promise
        .thenInBackground(^{
            return [OWSBackupAPI saveRecordsToCloudObjcWithRecords:records];
        })
        .thenInBackground(^{
            OWSAssertDebug(items.count == records.count);
            NSUInteger count = MIN(items.count, records.count);
            for (NSUInteger i = 0; i < count; i++) {
                OWSAttachmentExport *attachmentExport = items[i];
                CKRecord *record = records[i];
                NSString *recordName = record.recordID.recordName;
                OWSAssertDebug(recordName.length > 0);

                OWSBackupExportItem *exportItem =
                    [[OWSBackupExportItem alloc] initWithEncryptedItem:attachmentExport.encryptedItem];
                exportItem.recordName = recordName;
                exportItem.attachmentExport = attachmentExport;
                if (![SDS fitsInInt64WithNSNumber:exportItem.uncompressedDataLength]) {
                    OWSFailDebug(@"Invalid export item.");
                    continue;
                }
                [self.savedAttachmentItems addObject:exportItem];

                // Immediately save the record metadata to facilitate export resume.
                OWSBackupFragment *backupFragment = [[OWSBackupFragment alloc] initWithUniqueId:recordName];
                backupFragment.recordName = recordName;
                backupFragment.encryptionKey = exportItem.encryptedItem.encryptionKey;
                backupFragment.relativeFilePath = attachmentExport.relativeFilePath;
                backupFragment.attachmentId = attachmentExport.attachmentId;
                backupFragment.uncompressedDataLength = exportItem.uncompressedDataLength;
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    [backupFragment anyInsertWithTransaction:transaction];
                });

                OWSLogVerbose(@"saved attachment: %@ as %@",
                    attachmentExport.attachmentFilePath,
                    attachmentExport.relativeFilePath);
            }
        })
        .thenInBackground(^{
            cleanup();
        })
        .catchInBackground(^(NSError *error) {
            cleanup();

            return error;
        });
}

- (BOOL)tryToSkipAttachmentUpload:(OWSAttachmentExport *)attachmentExport
{
    if (!self.lastValidRecordNames) {
        return NO;
    }

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
    NSString *recordName =
        [OWSBackupAPI recordNameForPersistentFileWithRecipientId:self.recipientId fileId:attachmentExport.attachmentId];

    __block OWSBackupFragment *_Nullable lastBackupFragment;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        lastBackupFragment = [OWSBackupFragment anyFetchWithUniqueId:recordName transaction:transaction];
    }];

    if (!lastBackupFragment || ![self.lastValidRecordNames containsObject:recordName]) {
        return NO;
    }

    OWSAssertDebug(lastBackupFragment.encryptionKey.length > 0);
    OWSAssertDebug(lastBackupFragment.relativeFilePath.length > 0);

    // Recycle the metadata from the last backup's manifest.
    OWSBackupEncryptedItem *encryptedItem = [OWSBackupEncryptedItem new];
    encryptedItem.encryptionKey = lastBackupFragment.encryptionKey;
    attachmentExport.encryptedItem = encryptedItem;
    attachmentExport.relativeFilePath = lastBackupFragment.relativeFilePath;

    OWSBackupExportItem *exportItem =
        [[OWSBackupExportItem alloc] initWithEncryptedItem:attachmentExport.encryptedItem];
    exportItem.recordName = recordName;
    exportItem.attachmentExport = attachmentExport;
    [self.savedAttachmentItems addObject:exportItem];

    OWSLogVerbose(
        @"recycled attachment: %@ as %@", attachmentExport.attachmentFilePath, attachmentExport.relativeFilePath);
    return YES;
}

- (AnyPromise *)saveLocalProfileAvatarToCloud
{
    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    NSData *_Nullable localProfileAvatarData = self.profileManager.localProfileAvatarData;
    if (localProfileAvatarData.length < 1) {
        // No profile avatar to backup.
        return [AnyPromise promiseWithValue:@(1)];
    }
    OWSBackupEncryptedItem *_Nullable encryptedItem =
        [self.backupIO encryptDataAsTempFile:localProfileAvatarData encryptionKey:self.delegate.backupEncryptionKey];
    if (!encryptedItem) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not encrypt local profile avatar.")];
    }

    OWSBackupExportItem *exportItem = [[OWSBackupExportItem alloc] initWithEncryptedItem:encryptedItem];

    NSString *recordName =
        [OWSBackupAPI recordNameForEphemeralFileWithRecipientId:self.recipientId label:@"local-profile-avatar"];
    CKRecord *record =
        [OWSBackupAPI recordForFileUrl:[NSURL fileURLWithPath:encryptedItem.filePath] recordName:recordName];
    return [OWSBackupAPI saveRecordsToCloudObjcWithRecords:@[ record ]].thenInBackground(^{
        exportItem.recordName = recordName;
        self.localProfileAvatarItem = exportItem;
    });
}

- (AnyPromise *)saveManifestFileToCloud
{
    if (self.isComplete) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    OWSBackupEncryptedItem *_Nullable encryptedItem = [self writeManifestFile];
    if (!encryptedItem) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not generate manifest.")];
    }

    OWSBackupExportItem *exportItem = [[OWSBackupExportItem alloc] initWithEncryptedItem:encryptedItem];

    NSString *recordName = [OWSBackupAPI recordNameForManifestWithRecipientId:self.recipientId];
    CKRecord *record =
        [OWSBackupAPI recordForFileUrl:[NSURL fileURLWithPath:encryptedItem.filePath] recordName:recordName];
    return [OWSBackupAPI saveRecordsToCloudObjcWithRecords:@[ record ]].thenInBackground(^{
        exportItem.recordName = recordName;
        self.manifestItem = exportItem;
    });
}

- (nullable OWSBackupEncryptedItem *)writeManifestFile
{
    OWSAssertDebug(self.savedDatabaseItems.count > 0);
    OWSAssertDebug(self.savedAttachmentItems);
    OWSAssertDebug(self.jobTempDirPath.length > 0);
    OWSAssertDebug(self.backupIO);

    NSMutableDictionary *json = [@{
        kOWSBackup_ManifestKey_DatabaseFiles : [self jsonForItems:self.savedDatabaseItems],
        kOWSBackup_ManifestKey_AttachmentFiles : [self jsonForItems:self.savedAttachmentItems],
    } mutableCopy];

    NSString *_Nullable localGivenName = self.profileManager.localGivenName;
    if (localGivenName.length > 0) {
        json[kOWSBackup_ManifestKey_LocalProfileGivenName] = localGivenName;
    }

    NSString *_Nullable localFamilyName = self.profileManager.localFamilyName;
    if (localFamilyName.length > 0) {
        json[kOWSBackup_ManifestKey_LocalProfileFamilyName] = localFamilyName;
    }

    if (self.localProfileAvatarItem) {
        json[kOWSBackup_ManifestKey_LocalProfileAvatar] = [self jsonForItems:@[ self.localProfileAvatarItem ]];
    }

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

- (AnyPromise *)cleanUp
{
    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
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
    if (self.localProfileAvatarItem) {
        OWSBackupExportItem *item = self.localProfileAvatarItem;
        OWSAssertDebug(item.recordName.length > 0);
        OWSAssertDebug(![activeRecordNames containsObject:item.recordName]);
        [activeRecordNames addObject:item.recordName];
    }
    OWSAssertDebug(self.manifestItem.recordName.length > 0);
    OWSAssertDebug(![activeRecordNames containsObject:self.manifestItem.recordName]);
    [activeRecordNames addObject:self.manifestItem.recordName];

    // Because we do "lazy attachment restores", we need to include the record names for all
    // records that haven't been restored yet.
    NSArray<NSString *> *restoringRecordNames = [OWSBackup.shared attachmentRecordNamesForLazyRestore];
    [activeRecordNames addObjectsFromArray:restoringRecordNames];

    [self cleanUpMetadataCacheWithActiveRecordNames:activeRecordNames];

    return [self cleanUpCloudWithActiveRecordNames:activeRecordNames];
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
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSArray<NSString *> *allRecordNames = [OWSBackupFragment anyAllUniqueIdsWithTransaction:transaction];

        NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
        [obsoleteRecordNames addObjectsFromArray:allRecordNames];
        [obsoleteRecordNames minusSet:activeRecordNames];

        for (NSString *uniqueId in obsoleteRecordNames) {
            OWSBackupFragment *_Nullable instance =
                [OWSBackupFragment anyFetchWithUniqueId:uniqueId transaction:transaction];
            if (instance == nil) {
                OWSFailDebug(@"Missing instance.");
                continue;
            }
            [instance anyRemoveWithTransaction:transaction];
        }
    });
}

- (AnyPromise *)cleanUpCloudWithActiveRecordNames:(NSSet<NSString *> *)activeRecordNames
{
    OWSAssertDebug(activeRecordNames.count > 0);

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup export no longer active.")];
    }

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [OWSBackupAPI fetchAllRecordNamesWithRecipientId:self.recipientId
            success:^(NSArray<NSString *> *recordNames) {
                NSMutableSet<NSString *> *obsoleteRecordNames = [NSMutableSet new];
                [obsoleteRecordNames addObjectsFromArray:recordNames];
                [obsoleteRecordNames minusSet:activeRecordNames];

                OWSLogVerbose(@"recordNames: %zd - activeRecordNames: %zd = obsoleteRecordNames: %zd",
                    recordNames.count,
                    activeRecordNames.count,
                    obsoleteRecordNames.count);

                [self deleteRecordsFromCloud:[obsoleteRecordNames.allObjects mutableCopy]
                                deletedCount:0
                                  completion:^(NSError *_Nullable error) {
                                      // Cloud cleanup is non-critical so any error is recoverable.
                                      resolve(@(1));
                                  }];
            }
            failure:^(NSError *error) {
                // Cloud cleanup is non-critical so any error is recoverable.
                resolve(@(1));
            }];
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

    [OWSBackupAPI deleteRecordsFromCloudWithRecordNames:batchRecordNames
        success:^{
            [self deleteRecordsFromCloud:obsoleteRecordNames
                            deletedCount:deletedCount + batchRecordNames.count
                              completion:completion];
        }
        failure:^(NSError *error) {
            // Cloud cleanup is non-critical so any error is recoverable.
            [self deleteRecordsFromCloud:obsoleteRecordNames
                            deletedCount:deletedCount + batchRecordNames.count
                              completion:completion];
        }];
}

@end

NS_ASSUME_NONNULL_END
