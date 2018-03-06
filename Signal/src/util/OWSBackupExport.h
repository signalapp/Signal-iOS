//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBackupExport;

@protocol OWSBackupExportDelegate <NSObject>

// TODO: This should eventually be the backup key stored in the Signal Service
//       and retrieved with the backup PIN.
- (nullable NSData *)backupKey;

// Either backupExportDidSucceed:... or backupExportDidFail:... will
// be called exactly once on the main thread UNLESS:
//
// * The export was never started.
// * The export was cancelled.
- (void)backupExportDidSucceed:(OWSBackupExport *)backupExport;
- (void)backupExportDidFail:(OWSBackupExport *)backupExport error:(NSError *)error;

@end

//#pragma mark -

@class OWSPrimaryStorage;

@interface OWSBackupExport : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDelegate:(id<OWSBackupExportDelegate>)delegate
                  primaryStorage:(OWSPrimaryStorage *)primaryStorage;

- (void)startAsync;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
