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
NSString *const kOWSBackup_ManifestKey_RecordName = @"record_name";
NSString *const kOWSBackup_ManifestKey_EncryptionKey = @"encryption_key";
NSString *const kOWSBackup_ManifestKey_RelativeFilePath = @"relative_file_path";
NSString *const kOWSBackup_ManifestKey_DataSize = @"data_size";

NSString *const kOWSBackup_KeychainService = @"kOWSBackup_KeychainService";

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

@end

NS_ASSUME_NONNULL_END
