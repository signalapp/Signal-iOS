//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBackupImport;

@protocol OWSBackupImportDelegate <NSObject>

// TODO: This should eventually be the backup key stored in the Signal Service
//       and retrieved with the backup PIN.
- (nullable NSData *)backupKey;

// Either backupImportDidSucceed:... or backupImportDidFail:... will
// be called exactly once on the main thread UNLESS:
//
// * The import was never started.
// * The import was cancelled.
- (void)backupImportDidSucceed:(OWSBackupImport *)backupImport;
- (void)backupImportDidFail:(OWSBackupImport *)backupImport error:(NSError *)error;

- (void)backupImportDidUpdate:(OWSBackupImport *)backupImport
                  description:(nullable NSString *)description
                     progress:(nullable NSNumber *)progress;

@end

//#pragma mark -

@class OWSPrimaryStorage;

@interface OWSBackupImport : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<OWSBackupImportDelegate>)delegate
                  primaryStorage:(OWSPrimaryStorage *)primaryStorage;

- (void)startAsync;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
