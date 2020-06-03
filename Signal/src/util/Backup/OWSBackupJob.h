//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSBackupFragment.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kOWSBackup_ManifestKey_DatabaseFiles;
extern NSString *const kOWSBackup_ManifestKey_AttachmentFiles;
extern NSString *const kOWSBackup_ManifestKey_RecordName;
extern NSString *const kOWSBackup_ManifestKey_EncryptionKey;
extern NSString *const kOWSBackup_ManifestKey_RelativeFilePath;
extern NSString *const kOWSBackup_ManifestKey_AttachmentId;
extern NSString *const kOWSBackup_ManifestKey_DataSize;
extern NSString *const kOWSBackup_ManifestKey_LocalProfileAvatar;
extern NSString *const kOWSBackup_ManifestKey_LocalProfileGivenName;
extern NSString *const kOWSBackup_ManifestKey_LocalProfileFamilyName;

@class AnyPromise;
@class OWSBackupIO;
@class OWSBackupJob;
@class OWSBackupManifestContents;

typedef void (^OWSBackupJobBoolCompletion)(BOOL success);
typedef void (^OWSBackupJobCompletion)(NSError *_Nullable error);
typedef void (^OWSBackupJobManifestSuccess)(OWSBackupManifestContents *manifest);
typedef void (^OWSBackupJobManifestFailure)(NSError *error);

@interface OWSBackupManifestContents : NSObject

@property (nonatomic) NSArray<OWSBackupFragment *> *databaseItems;
@property (nonatomic) NSArray<OWSBackupFragment *> *attachmentsItems;
@property (nonatomic, nullable) OWSBackupFragment *localProfileAvatarItem;
@property (nonatomic, nullable) NSString *localProfileGivenName;
@property (nonatomic, nullable) NSString *localProfileFamilyName;

@end

#pragma mark -

@protocol OWSBackupJobDelegate <NSObject>

- (nullable NSData *)backupEncryptionKey;

// Either backupJobDidSucceed:... or backupJobDidFail:... will
// be called exactly once on the main thread UNLESS:
//
// * The job was never started.
// * The job was cancelled.
- (void)backupJobDidSucceed:(OWSBackupJob *)backupJob;
- (void)backupJobDidFail:(OWSBackupJob *)backupJob error:(NSError *)error;

- (void)backupJobDidUpdate:(OWSBackupJob *)backupJob
               description:(nullable NSString *)description
                  progress:(nullable NSNumber *)progress;

@end

#pragma mark -

@interface OWSBackupJob : NSObject

@property (nonatomic, weak, readonly) id<OWSBackupJobDelegate> delegate;

@property (nonatomic, readonly) NSString *recipientId;

// Indicates that the backup succeeded, failed or was cancelled.
@property (atomic, readonly) BOOL isComplete;

@property (nonatomic, readonly) NSString *jobTempDirPath;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<OWSBackupJobDelegate>)delegate recipientId:(NSString *)recipientId;

#pragma mark - Private

- (BOOL)ensureJobTempDir;

- (void)cancel;
- (void)succeed;
- (void)failWithErrorDescription:(NSString *)description;
- (void)failWithError:(NSError *)error;
- (void)updateProgressWithDescription:(nullable NSString *)description progress:(nullable NSNumber *)progress;

#pragma mark - Manifest

- (AnyPromise *)downloadAndProcessManifestWithBackupIO:(OWSBackupIO *)backupIO __attribute__((warn_unused_result));

@end

NS_ASSUME_NONNULL_END
