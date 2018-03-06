//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupExport.h"
#import "Signal-Swift.h"
#import "zlib.h"
#import <Curve25519Kit/Randomness.h>
#import <SSZipArchive/SSZipArchive.h>
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

typedef void (^OWSBackupExportBoolCompletion)(BOOL success);
typedef void (^OWSBackupExportCompletion)(NSError *_Nullable error);

#pragma mark -

@interface OWSAttachmentExport : NSObject

@property (nonatomic) NSString *exportDirPath;
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
    OWSAssert(self.exportDirPath.length > 0);
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

    NSString *_Nullable tempFilePath = [self encryptAsTempFile:self.attachmentFilePath];
    if (!tempFilePath) {
        DDLogError(@"%@ attachment could not be encrypted.", self.logTag);
        OWSFail(@"%@ attachment could not be encrypted: %@", self.logTag, self.attachmentFilePath);
        return;
    }
}

- (nullable NSString *)encryptAsTempFile:(NSString *)srcFilePath
{
    OWSAssert(self.exportDirPath.length > 0);

    // TODO: Encrypt the file using self.delegate.backupKey;

    NSString *dstFilePath = [self.exportDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL success = [fileManager copyItemAtPath:srcFilePath toPath:dstFilePath error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing encrypted file: %@", self.logTag, error);
        return nil;
    }
    return dstFilePath;
}

@end

#pragma mark -

@interface OWSBackupExport () <SSZipArchiveDelegate>

@property (nonatomic, weak) id<OWSBackupExportDelegate> delegate;

@property (nonatomic, nullable) YapDatabaseConnection *srcDBConnection;

@property (nonatomic, nullable) YapDatabaseConnection *dstDBConnection;

// Indicates that the backup succeeded, failed or was cancelled.
@property (atomic) BOOL isComplete;

@property (nonatomic, nullable) OWSBackupStorage *backupStorage;

@property (nonatomic, nullable) NSData *databaseSalt;

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

@property (nonatomic) NSString *exportDirPath;

@end

#pragma mark -

@implementation OWSBackupExport

- (instancetype)initWithDelegate:(id<OWSBackupExportDelegate>)delegate
                  primaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(primaryStorage);
    OWSAssert([OWSStorage isStorageReady]);

    self.delegate = delegate;
    _srcDBConnection = primaryStorage.newDatabaseConnection;

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (self.exportDirPath) {
        [OWSFileSystem deleteFileIfExists:self.exportDirPath];
    }
}

- (void)startAsync
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    __weak OWSBackupExport *weakSelf = self;
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
    __weak OWSBackupExport *weakSelf = self;
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
        if (![self exportDatabase]) {
            [self failWithErrorDescription:
                      NSLocalizedString(@"BACKUP_EXPORT_ERROR_COULD_NOT_EXPORT",
                          @"Error indicating the a backup export could not export the user's data.")];
            return;
        }
        if (self.isComplete) {
            return;
        }
        [self saveToCloud:^(NSError *_Nullable error) {
            if (error) {
                [weakSelf failWithError:error];
            } else {
                [weakSelf succeed];
            }
        }];
    }];
}

- (void)configureExport:(OWSBackupExportBoolCompletion)completion
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSString *temporaryDirectory = NSTemporaryDirectory();
    self.exportDirPath = [temporaryDirectory stringByAppendingString:[NSUUID UUID].UUIDString];
    NSString *exportDatabaseDirPath = [self.exportDirPath stringByAppendingPathComponent:@"Database"];
    self.databaseSalt = [Randomness generateRandomBytes:(int)kSQLCipherSaltLength];

    if (![OWSFileSystem ensureDirectoryExists:self.exportDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create exportDirPath.", self.logTag);
        return completion(NO);
    }
    if (![OWSFileSystem ensureDirectoryExists:exportDatabaseDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create exportDatabaseDirPath.", self.logTag);
        return completion(NO);
    }
    if (!self.databaseSalt) {
        OWSProdLogAndFail(@"%@ Could not create databaseSalt.", self.logTag);
        return completion(NO);
    }
    __weak OWSBackupExport *weakSelf = self;
    BackupStorageKeySpecBlock keySpecBlock = ^{
        NSData *_Nullable backupKey = [weakSelf.delegate backupKey];
        if (!backupKey) {
            return (NSData *)nil;
        }
        NSData *_Nullable databaseSalt = weakSelf.databaseSalt;
        if (!databaseSalt) {
            return (NSData *)nil;
        }
        OWSCAssert(backupKey.length > 0);
        NSData *_Nullable keySpec =
            [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:backupKey saltData:databaseSalt];
        return keySpec;
    };
    self.backupStorage =
        [[OWSBackupStorage alloc] initBackupStorageWithDatabaseDirPath:exportDatabaseDirPath keySpecBlock:keySpecBlock];
    if (!self.backupStorage) {
        OWSProdLogAndFail(@"%@ Could not create backupStorage.", self.logTag);
        return completion(NO);
    }
    _dstDBConnection = self.backupStorage.newDatabaseConnection;
    if (!self.dstDBConnection) {
        OWSProdLogAndFail(@"%@ Could not create dstDBConnection.", self.logTag);
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

    __block unsigned long long copiedThreads = 0;
    __block unsigned long long copiedInteractions = 0;
    __block unsigned long long copiedEntities = 0;
    __block unsigned long long copiedAttachments = 0;

    self.attachmentFilePathMap = [NSMutableDictionary new];

    [self.srcDBConnection readWithBlock:^(YapDatabaseReadTransaction *srcTransaction) {
        [self.dstDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *dstTransaction) {
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
    self.dstDBConnection = nil;
    self.backupStorage = nil;

    return YES;
}

- (void)saveToCloud:(OWSBackupExportCompletion)completion
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.databaseRecordMap = [NSMutableDictionary new];
    self.attachmentRecordMap = [NSMutableDictionary new];

    [self saveNextFileToCloud:completion];
}

- (void)saveNextFileToCloud:(OWSBackupExportCompletion)completion
{
    if (self.isComplete) {
        return;
    }

    __weak OWSBackupExport *weakSelf = self;

    if (self.databaseFilePaths.count > 0) {
        NSString *filePath = self.databaseFilePaths.lastObject;
        [self.databaseFilePaths removeLastObject];
        // Database files are encrypted and can be safely stored unencrypted in the cloud.
        // TODO: Security review.
        [OWSBackupAPI saveEphemeralDatabaseFileToCloudWithFileUrl:[NSURL fileURLWithPath:filePath]
            success:^(NSString *recordName) {
                // Ensure that we continue to perform the backup export
                // off the main thread.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    OWSBackupExport *strongSelf = weakSelf;
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
        attachmentExport.exportDirPath = self.exportDirPath;
        attachmentExport.attachmentId = attachmentId;
        attachmentExport.attachmentFilePath = attachmentFilePath;

        [OWSBackupAPI savePersistentFileOnceToCloudWithFileId:attachmentId
            fileUrlBlock:^{
                [attachmentExport prepareForUpload];
                if (attachmentExport.tempFilePath.length < 1 || attachmentExport.relativeFilePath.length < 1) {
                    return (NSURL *)nil;
                }
                return [NSURL fileURLWithPath:attachmentExport.tempFilePath];
            }
            success:^(NSString *recordName) {
                // Ensure that we continue to perform the backup export
                // off the main thread.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    OWSBackupExport *strongSelf = weakSelf;
                    if (!strongSelf) {
                        return;
                    }
                    strongSelf.attachmentRecordMap[recordName] = attachmentExport.relativeFilePath;
                    [strongSelf saveNextFileToCloud:completion];
                });
            }
            failure:^(NSError *error) {
                // Ensure that we continue to perform the backup export
                // off the main thread.
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
                // Ensure that we continue to perform the backup export
                // off the main thread.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    OWSBackupExport *strongSelf = weakSelf;
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

- (nullable NSString *)encryptAsTempFile:(NSString *)srcFilePath
{
    OWSAssert(self.exportDirPath.length > 0);

    // TODO: Encrypt the file using self.delegate.backupKey;

    NSString *dstFilePath = [self.exportDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL success = [fileManager copyItemAtPath:srcFilePath toPath:dstFilePath error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing encrypted file: %@", self.logTag, error);
        return nil;
    }
    return dstFilePath;
}

- (BOOL)writeManifestFile
{
    OWSAssert(self.databaseRecordMap.count > 0);
    OWSAssert(self.attachmentRecordMap);
    OWSAssert(self.exportDirPath.length > 0);

    NSDictionary *json = @{
        @"database_files" : self.databaseRecordMap,
        @"attachment_files" : self.attachmentRecordMap,
    };
    NSError *error;
    NSData *_Nullable jsonData =
        [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        OWSProdLogAndFail(@"%@ error encoding manifest file: %@", self.logTag, error);
        return NO;
    }
    // TODO: Encrypt the manifest.
    self.manifestFilePath = [self.exportDirPath stringByAppendingPathComponent:@"manifest.json"];
    if (![jsonData writeToFile:self.manifestFilePath atomically:YES]) {
        OWSProdLogAndFail(@"%@ error writing manifest file: %@", self.logTag, error);
        return NO;
    }
    return YES;
}

- (void)cancel
{
    OWSAssertIsOnMainThread();

    // TODO:
    self.isComplete = YES;
}

- (void)succeed
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            return;
        }
        self.isComplete = YES;
        [self.delegate backupExportDidSucceed:self];
    });
    // TODO:
}

- (void)failWithErrorDescription:(NSString *)description
{
    [self failWithError:OWSErrorWithCodeDescription(OWSErrorCodeExportBackupFailed, description)];
}

- (void)failWithError:(NSError *)error
{
    OWSProdLogAndFail(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, error);

    // TODO:

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            return;
        }
        self.isComplete = YES;
        [self.delegate backupExportDidFail:self error:error];
    });
}

@end

NS_ASSUME_NONNULL_END
