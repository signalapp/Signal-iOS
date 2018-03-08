//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationNameBackupStateDidChange;

typedef void (^OWSBackupBoolBlock)(BOOL value);
typedef void (^OWSBackupErrorBlock)(NSError *error);

typedef NS_ENUM(NSUInteger, OWSBackupState) {
    // Has never backed up, not trying to backup yet.
    OWSBackupState_Idle = 0,
    // Backing up.
    OWSBackupState_InProgress,
    // Last backup failed.
    OWSBackupState_Failed,
    // Last backup succeeded.
    OWSBackupState_Succeeded,
};

@class TSThread;

@interface OWSBackup : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)setup;

#pragma mark - Backup Export

@property (nonatomic, readonly) OWSBackupState backupExportState;
// If a "backup export" is in progress (see backupExportState),
// backupExportDescription _might_ contain a string that describes
// the current phase and backupExportProgress _might_ contain a
// 0.0<=x<=1.0 progress value that indicates progress within the
// current phase.
@property (nonatomic, readonly, nullable) NSString *backupExportDescription;
@property (nonatomic, readonly, nullable) NSNumber *backupExportProgress;

- (BOOL)isBackupEnabled;
- (void)setIsBackupEnabled:(BOOL)value;

#pragma mark - Backup Import

@property (nonatomic, readonly) OWSBackupState backupImportState;
// If a "backup import" is in progress (see backupImportState),
// backupImportDescription _might_ contain a string that describes
// the current phase and backupImportProgress _might_ contain a
// 0.0<=x<=1.0 progress value that indicates progress within the
// current phase.
@property (nonatomic, readonly, nullable) NSString *backupImportDescription;
@property (nonatomic, readonly, nullable) NSNumber *backupImportProgress;

- (void)checkCanImportBackup:(OWSBackupBoolBlock)success failure:(OWSBackupErrorBlock)failure;

// TODO: After a successful import, we should enable backup and
//       preserve our PIN and/or private key so that restored users
//       continues to backup.
- (void)tryToImportBackup;

@end

NS_ASSUME_NONNULL_END
