//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kOWSBackup_ManifestKey_DatabaseFiles;
extern NSString *const kOWSBackup_ManifestKey_AttachmentFiles;
extern NSString *const kOWSBackup_ManifestKey_DatabaseKeySpec;

typedef void (^OWSBackupJobBoolCompletion)(BOOL success);
typedef void (^OWSBackupJobCompletion)(NSError *_Nullable error);

@class OWSBackupJob;

@protocol OWSBackupJobDelegate <NSObject>

// TODO: This should eventually be the backup key stored in the Signal Service
//       and retrieved with the backup PIN.
- (nullable NSData *)backupKey;

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

@class OWSPrimaryStorage;

@interface OWSBackupJob : NSObject

@property (nonatomic, weak, readonly) id<OWSBackupJobDelegate> delegate;

// Indicates that the backup succeeded, failed or was cancelled.
@property (atomic, readonly) BOOL isComplete;

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

@property (nonatomic, readonly) NSString *jobTempDirPath;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<OWSBackupJobDelegate>)delegate primaryStorage:(OWSPrimaryStorage *)primaryStorage;

#pragma mark - Private

- (BOOL)ensureJobTempDir;

- (void)cancel;
- (void)succeed;
- (void)failWithErrorDescription:(NSString *)description;
- (void)failWithError:(NSError *)error;
- (void)updateProgressWithDescription:(nullable NSString *)description progress:(nullable NSNumber *)progress;


#pragma mark - Database KeySpec

+ (nullable NSData *)loadDatabaseKeySpecWithKeychainKey:(NSString *)keychainKey;
+ (BOOL)storeDatabaseKeySpec:(NSData *)data keychainKey:(NSString *)keychainKey;
+ (BOOL)generateRandomDatabaseKeySpecWithKeychainKey:(NSString *)keychainKey;

#pragma mark - Encryption

+ (nullable NSString *)encryptFileAsTempFile:(NSString *)srcFilePath
                              jobTempDirPath:(NSString *)jobTempDirPath
                                    delegate:(id<OWSBackupJobDelegate>)delegate;

+ (nullable NSString *)encryptDataAsTempFile:(NSData *)data
                              jobTempDirPath:(NSString *)jobTempDirPath
                                    delegate:(id<OWSBackupJobDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
