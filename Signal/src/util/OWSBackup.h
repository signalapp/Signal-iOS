//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSBackup_FileExtension;

@protocol OWSBackupDelegate <NSObject>

- (void)backupStateDidChange;

- (void)backupProgressDidChange;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSBackupState) {
    OWSBackupState_InProgress,
    OWSBackupState_Cancelled,
    OWSBackupState_Complete,
    OWSBackupState_Failed,
};

@class TSThread;

// We restore backups as part of the app launch process.
//
// applicationDidFinishLaunching must complete quickly even for
// large backups, to prevent the app from being killed on launch.
// Therefore, we break up backup import/restoration into two parts:
//
// * Preparation (which includes the costly decryption/unzip of the
//   backup file)
// * Completion (file moves, NSUserDefaults writes, keychain writes).
//
// To protect data during backup and restore, we:
//
// * Optionally encrypt backup files with a password.
// * Separately encrypt files containing keychain & NSUserDefaults data.
// * Delete data from disk ASAP.
@interface OWSBackup : NSObject

@property (nonatomic, weak) id<OWSBackupDelegate> delegate;

// An instance of `OWSBackup` is used for three separate tasks:
//
// * Backup export
// * Backup import preparation
// * Backup import completion
//
// The "backup state" and "progress" apply to all three tasks.
@property (nonatomic, readonly) OWSBackupState backupState;
@property (nonatomic, readonly) CGFloat backupProgress;

// If non-nil, backup is encrypted.
@property (nonatomic, nullable, readonly) NSString *backupPassword;

// Only applies to "backup export" task.
@property (nonatomic, nullable, readonly) TSThread *currentThread;

@property (nonatomic, readonly) NSString *backupZipPath;

- (void)exportBackup:(nullable TSThread *)currentThread skipPassword:(BOOL)skipPassword;

- (void)importBackup:(NSString *)backupZipPath password:(NSString *_Nullable)password;

- (void)cancel;

+ (void)applicationDidFinishLaunching;

@end

NS_ASSUME_NONNULL_END
