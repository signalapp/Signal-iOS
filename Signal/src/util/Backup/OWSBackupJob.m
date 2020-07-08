//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupJob.h"
#import "OWSBackupIO.h"
#import "Signal-Swift.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/StorageCoordinator.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ManifestKey_DatabaseFiles = @"database_files";
NSString *const kOWSBackup_ManifestKey_AttachmentFiles = @"attachment_files";
NSString *const kOWSBackup_ManifestKey_RecordName = @"record_name";
NSString *const kOWSBackup_ManifestKey_EncryptionKey = @"encryption_key";
NSString *const kOWSBackup_ManifestKey_RelativeFilePath = @"relative_file_path";
NSString *const kOWSBackup_ManifestKey_AttachmentId = @"attachment_id";
NSString *const kOWSBackup_ManifestKey_DataSize = @"data_size";
NSString *const kOWSBackup_ManifestKey_LocalProfileAvatar = @"local_profile_avatar";
NSString *const kOWSBackup_ManifestKey_LocalProfileGivenName = @"local_profile_name";
NSString *const kOWSBackup_ManifestKey_LocalProfileFamilyName = @"local_profile_family_name";

NSString *const kOWSBackup_KeychainService = @"kOWSBackup_KeychainService";

@implementation OWSBackupManifestContents

@end

#pragma mark -

@interface OWSBackupJob ()

@property (nonatomic, weak) id<OWSBackupJobDelegate> delegate;

@property (nonatomic) NSString *recipientId;

@property (atomic) BOOL isComplete;
@property (atomic) BOOL hasSucceeded;

@property (nonatomic) NSString *jobTempDirPath;

@end

#pragma mark -

@implementation OWSBackupJob

#pragma mark - Dependencies

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

#pragma mark -

- (instancetype)initWithDelegate:(id<OWSBackupJobDelegate>)delegate recipientId:(NSString *)recipientId
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug([self.storageCoordinator isStorageReady]);
    OWSAssertDebug(AppReadiness.isAppReady);

    self.delegate = delegate;
    self.recipientId = recipientId;

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (self.jobTempDirPath) {
        [OWSFileSystem deleteFileIfExists:self.jobTempDirPath];
    }
}

- (BOOL)ensureJobTempDir
{
    OWSLogVerbose(@"");

    // TODO: Exports should use a new directory each time, but imports
    // might want to use a predictable directory so that repeated
    // import attempts can reuse downloads from previous attempts.
    NSString *temporaryDirectory = OWSTemporaryDirectory();
    self.jobTempDirPath = [temporaryDirectory stringByAppendingPathComponent:[NSUUID UUID].UUIDString];

    if (![OWSFileSystem ensureDirectoryExists:self.jobTempDirPath]) {
        OWSFailDebug(@"Could not create jobTempDirPath.");
        return NO;
    }
    return YES;
}

#pragma mark -

- (void)cancel
{
    OWSAssertIsOnMainThread();

    self.isComplete = YES;
}

- (void)succeed
{
    OWSLogInfo(@"");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            OWSAssertDebug(!self.hasSucceeded);
            return;
        }
        self.isComplete = YES;
        
        // There's a lot of asynchrony in these backup jobs;
        // ensure we only end up finishing these jobs once.
        OWSAssertDebug(!self.hasSucceeded);
        self.hasSucceeded = YES;
        
        [self.delegate backupJobDidSucceed:self];
    });
}

- (void)failWithErrorDescription:(NSString *)description
{
    [self failWithError:OWSErrorWithCodeDescription(OWSErrorCodeImportBackupFailed, description)];
}

- (void)failWithError:(NSError *)error
{
    OWSFailDebug(@"%@", error);

    dispatch_async(dispatch_get_main_queue(), ^{
        OWSAssertDebug(!self.hasSucceeded);
        if (self.isComplete) {
            return;
        }
        self.isComplete = YES;
        [self.delegate backupJobDidFail:self error:error];
    });
}

- (void)updateProgressWithDescription:(nullable NSString *)description progress:(nullable NSNumber *)progress
{
    OWSLogInfo(@"");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            return;
        }
        [self.delegate backupJobDidUpdate:self description:description progress:progress];
    });
}

#pragma mark - Manifest

- (AnyPromise *)downloadAndProcessManifestWithBackupIO:(OWSBackupIO *)backupIO
{
    OWSAssertDebug(backupIO);

    OWSLogVerbose(@"");

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup job no longer active.")];
    }

    return
        [OWSBackupAPI downloadManifestFromCloudObjcWithRecipientId:self.recipientId].thenInBackground(^(NSData *data) {
            return [self processManifest:data backupIO:backupIO];
        });
}

- (AnyPromise *)processManifest:(NSData *)manifestDataEncrypted backupIO:(OWSBackupIO *)backupIO
{
    OWSAssertDebug(manifestDataEncrypted.length > 0);
    OWSAssertDebug(backupIO);

    if (self.isComplete) {
        // Job was aborted.
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Backup job no longer active.")];
    }

    OWSLogVerbose(@"");

    NSData *_Nullable manifestDataDecrypted =
        [backupIO decryptDataAsData:manifestDataEncrypted encryptionKey:self.delegate.backupEncryptionKey];
    if (!manifestDataDecrypted) {
        OWSFailDebug(@"Could not decrypt manifest.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not decrypt manifest.")];
    }

    NSError *error;
    NSDictionary<NSString *, id> *_Nullable json =
        [NSJSONSerialization JSONObjectWithData:manifestDataDecrypted options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"Could not download manifest.");
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"Could not download manifest.")];
    }

    OWSLogVerbose(@"json: %@", json);

    NSArray<OWSBackupFragment *> *_Nullable databaseItems =
        [self parseManifestItems:json key:kOWSBackup_ManifestKey_DatabaseFiles];
    if (!databaseItems) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"No database items in manifest.")];
    }
    NSArray<OWSBackupFragment *> *_Nullable attachmentsItems =
        [self parseManifestItems:json key:kOWSBackup_ManifestKey_AttachmentFiles];
    if (!attachmentsItems) {
        return [AnyPromise promiseWithValue:OWSBackupErrorWithDescription(@"No attachment items in manifest.")];
    }

    NSArray<OWSBackupFragment *> *_Nullable localProfileAvatarItems;
    if ([self parseManifestItem:json key:kOWSBackup_ManifestKey_LocalProfileAvatar]) {
        localProfileAvatarItems = [self parseManifestItems:json key:kOWSBackup_ManifestKey_LocalProfileAvatar];
    }

    NSString *_Nullable localProfileGivenName = [self parseManifestItem:json
                                                                    key:kOWSBackup_ManifestKey_LocalProfileGivenName];
    NSString *_Nullable localProfileFamilyName = [self parseManifestItem:json
                                                                     key:kOWSBackup_ManifestKey_LocalProfileFamilyName];

    OWSBackupManifestContents *contents = [OWSBackupManifestContents new];
    contents.databaseItems = databaseItems;
    contents.attachmentsItems = attachmentsItems;
    contents.localProfileAvatarItem = localProfileAvatarItems.firstObject;
    if ([localProfileGivenName isKindOfClass:[NSString class]]) {
        contents.localProfileGivenName = localProfileGivenName;
    } else if (localProfileGivenName) {
        OWSFailDebug(@"Invalid localProfileGivenName: %@", [localProfileGivenName class]);
    }
    if ([localProfileFamilyName isKindOfClass:[NSString class]]) {
        contents.localProfileFamilyName = localProfileFamilyName;
    } else if (localProfileFamilyName) {
        OWSFailDebug(@"Invalid localProfileFamilyName: %@", [localProfileFamilyName class]);
    }

    return [AnyPromise promiseWithValue:contents];
}

- (nullable id)parseManifestItem:(id)json key:(NSString *)key
{
    OWSAssertDebug(json);
    OWSAssertDebug(key.length);

    if (![json isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"manifest has invalid data.");
        return nil;
    }
    id _Nullable value = json[key];
    return value;
}

- (nullable NSArray<OWSBackupFragment *> *)parseManifestItems:(id)json key:(NSString *)key
{
    OWSAssertDebug(json);
    OWSAssertDebug(key.length);

    if (![json isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"manifest has invalid data.");
        return nil;
    }
    NSArray *itemMaps = json[key];
    if (![itemMaps isKindOfClass:[NSArray class]]) {
        OWSFailDebug(@"manifest has invalid data.");
        return nil;
    }
    NSMutableArray<OWSBackupFragment *> *items = [NSMutableArray new];
    for (NSDictionary *itemMap in itemMaps) {
        if (![itemMap isKindOfClass:[NSDictionary class]]) {
            OWSFailDebug(@"manifest has invalid item.");
            return nil;
        }
        NSString *_Nullable recordName = itemMap[kOWSBackup_ManifestKey_RecordName];
        NSString *_Nullable encryptionKeyString = itemMap[kOWSBackup_ManifestKey_EncryptionKey];
        NSString *_Nullable relativeFilePath = itemMap[kOWSBackup_ManifestKey_RelativeFilePath];
        NSString *_Nullable attachmentId = itemMap[kOWSBackup_ManifestKey_AttachmentId];
        NSNumber *_Nullable uncompressedDataLength = itemMap[kOWSBackup_ManifestKey_DataSize];
        if (![recordName isKindOfClass:[NSString class]]) {
            OWSFailDebug(@"manifest has invalid recordName: %@.", recordName);
            return nil;
        }
        if (![encryptionKeyString isKindOfClass:[NSString class]]) {
            OWSFailDebug(@"manifest has invalid encryptionKey.");
            return nil;
        }
        // relativeFilePath is an optional field.
        if (relativeFilePath && ![relativeFilePath isKindOfClass:[NSString class]]) {
            OWSLogDebug(@"manifest has invalid relativeFilePath: %@.", relativeFilePath);
            OWSFailDebug(@"manifest has invalid relativeFilePath");
            return nil;
        }
        // attachmentId is an optional field.
        if (attachmentId && ![attachmentId isKindOfClass:[NSString class]]) {
            OWSLogDebug(@"manifest has invalid attachmentId: %@.", attachmentId);
            OWSFailDebug(@"manifest has invalid attachmentId");
            return nil;
        }
        NSData *_Nullable encryptionKey = [NSData dataFromBase64String:encryptionKeyString];
        if (!encryptionKey) {
            OWSFailDebug(@"manifest has corrupt encryptionKey");
            return nil;
        }
        // uncompressedDataLength is an optional field.
        if (uncompressedDataLength != nil && ![uncompressedDataLength isKindOfClass:[NSNumber class]]) {
            OWSFailDebug(@"manifest has invalid uncompressedDataLength: %@.", uncompressedDataLength);
            return nil;
        }
        if (uncompressedDataLength != nil && ![SDS fitsInInt64WithNSNumber:uncompressedDataLength]) {
            OWSFailDebug(@"Invalid export item.");
            return nil;
        }

        OWSBackupFragment *item = [[OWSBackupFragment alloc] initWithUniqueId:recordName];
        item.recordName = recordName;
        item.encryptionKey = encryptionKey;
        item.relativeFilePath = relativeFilePath;
        item.attachmentId = attachmentId;
        item.uncompressedDataLength = uncompressedDataLength;
        [items addObject:item];
    }
    return items;
}

@end

NS_ASSUME_NONNULL_END
