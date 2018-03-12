//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationNameBackupStateDidChange;

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

@property (nonatomic, readonly) OWSBackupState backupExportState;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (BOOL)isBackupEnabled;
- (void)setIsBackupEnabled:(BOOL)value;

- (void)setup;

@end

NS_ASSUME_NONNULL_END
