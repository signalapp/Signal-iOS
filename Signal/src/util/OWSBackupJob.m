//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupJob.h"
#import "Signal-Swift.h"
#import <Curve25519Kit/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSBackup_ManifestKey_DatabaseFiles = @"database_files";
NSString *const kOWSBackup_ManifestKey_AttachmentFiles = @"attachment_files";
NSString *const kOWSBackup_ManifestKey_DatabaseKeySpec = @"database_key_spec";

NSString *const kOWSBackup_KeychainService = @"kOWSBackup_KeychainService";

NSString *const kOWSBackup_Snapshot_Collection = @"kOWSBackup_Snapshot_Collection";
NSString *const kOWSBackup_Snapshot_ValidKey = @"kOWSBackup_Snapshot_ValidKey";

@interface OWSBackupJob ()

@property (nonatomic, weak) id<OWSBackupJobDelegate> delegate;

@property (atomic) BOOL isComplete;
@property (atomic) BOOL hasSucceeded;

@property (nonatomic) OWSPrimaryStorage *primaryStorage;

@property (nonatomic) NSString *jobTempDirPath;

@end

#pragma mark -

@implementation OWSBackupJob

- (instancetype)initWithDelegate:(id<OWSBackupJobDelegate>)delegate primaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(primaryStorage);
    OWSAssert([OWSStorage isStorageReady]);

    self.delegate = delegate;
    self.primaryStorage = primaryStorage;

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (self.jobTempDirPath) {
        [OWSFileSystem deleteFileIfExists:self.jobTempDirPath];
    }
}

- (BOOL)ensureJobTempDir
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // TODO: Exports should use a new directory each time, but imports
    // might want to use a predictable directory so that repeated
    // import attempts can reuse downloads from previous attempts.
    NSString *temporaryDirectory = NSTemporaryDirectory();
    self.jobTempDirPath = [temporaryDirectory stringByAppendingString:[NSUUID UUID].UUIDString];

    if (![OWSFileSystem ensureDirectoryExists:self.jobTempDirPath]) {
        OWSProdLogAndFail(@"%@ Could not create jobTempDirPath.", self.logTag);
        return NO;
    }
    if (![OWSFileSystem protectFileOrFolderAtPath:self.jobTempDirPath]) {
        OWSProdLogAndFail(@"%@ Could not protect jobTempDirPath.", self.logTag);
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
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            OWSAssert(!self.hasSucceeded);
            return;
        }
        self.isComplete = YES;

        // There's a lot of asynchrony in these backup jobs;
        // ensure we only end up finishing these jobs once.
        OWSAssert(!self.hasSucceeded);
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
    OWSProdLogAndFail(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, error);

    dispatch_async(dispatch_get_main_queue(), ^{
        OWSAssert(!self.hasSucceeded);
        if (self.isComplete) {
            return;
        }
        self.isComplete = YES;
        [self.delegate backupJobDidFail:self error:error];
    });
}

- (void)updateProgressWithDescription:(nullable NSString *)description progress:(nullable NSNumber *)progress
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isComplete) {
            return;
        }
        [self.delegate backupJobDidUpdate:self description:description progress:progress];
    });
}

#pragma mark - Database KeySpec

+ (nullable NSData *)loadDatabaseKeySpecWithKeychainKey:(NSString *)keychainKey
{
    OWSAssert(keychainKey.length > 0);

    NSError *error;
    NSData *_Nullable value =
        [SAMKeychain passwordDataForService:kOWSBackup_KeychainService account:keychainKey error:&error];
    if (!value || error) {
        DDLogError(@"%@ could not load database keyspec: %@", self.logTag, error);
    }
    return value;
}

+ (BOOL)storeDatabaseKeySpec:(NSData *)data keychainKey:(NSString *)keychainKey
{
    OWSAssert(keychainKey.length > 0);
    OWSAssert(data.length > 0);

    NSError *error;
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    BOOL success =
        [SAMKeychain setPasswordData:data forService:kOWSBackup_KeychainService account:keychainKey error:&error];
    if (!success || error) {
        OWSFail(@"%@ Could not store database keyspec: %@.", self.logTag, error);
        return NO;
    } else {
        return YES;
    }
}

+ (BOOL)generateRandomDatabaseKeySpecWithKeychainKey:(NSString *)keychainKey
{
    OWSAssert(keychainKey.length > 0);

    NSData *_Nullable databaseKeySpec = [Randomness generateRandomBytes:(int)kSQLCipherKeySpecLength];
    if (!databaseKeySpec) {
        OWSFail(@"%@ Could not generate database keyspec.", self.logTag);
        return NO;
    }

    return [self storeDatabaseKeySpec:databaseKeySpec keychainKey:keychainKey];
}

#pragma mark - Encryption

+ (nullable NSString *)encryptFileAsTempFile:(NSString *)srcFilePath
                              jobTempDirPath:(NSString *)jobTempDirPath
                                    delegate:(id<OWSBackupJobDelegate>)delegate
{
    OWSAssert(srcFilePath.length > 0);
    OWSAssert(jobTempDirPath.length > 0);
    OWSAssert(delegate);

    // TODO: Encrypt the file using self.delegate.backupKey;
    NSData *_Nullable backupKey = [delegate backupKey];
    OWSAssert(backupKey);

    NSString *dstFilePath = [jobTempDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    BOOL success = [fileManager copyItemAtPath:srcFilePath toPath:dstFilePath error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing encrypted file: %@", self.logTag, error);
        return nil;
    }
    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
    return dstFilePath;
}

+ (nullable NSString *)encryptDataAsTempFile:(NSData *)data
                              jobTempDirPath:(NSString *)jobTempDirPath
                                    delegate:(id<OWSBackupJobDelegate>)delegate
{
    OWSAssert(data);
    OWSAssert(jobTempDirPath.length > 0);
    OWSAssert(delegate);

    // TODO: Encrypt the file using self.delegate.backupKey;
    NSData *_Nullable backupKey = [delegate backupKey];
    OWSAssert(backupKey);

    NSString *dstFilePath = [jobTempDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error;
    BOOL success = [data writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing encrypted file: %@", self.logTag, error);
        return nil;
    }
    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
    return dstFilePath;
}

@end

NS_ASSUME_NONNULL_END
