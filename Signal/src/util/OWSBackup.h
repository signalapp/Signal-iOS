//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// extern NSString *const OWSBackup_FileExtension;

extern NSString *const NSNotificationNameBackupStateDidChange;

//@protocol OWSBackupDelegate <NSObject>
//
//- (void)backupStateDidChange;
//
//- (void)backupProgressDidChange;
//
//@end
//
//#pragma mark -

typedef NS_ENUM(NSUInteger, OWSBackupState) {
    OWSBackupState_AtRest = 0,
    OWSBackupState_InProgress,
    //    OWSBackupState_Cancelled,
    OWSBackupState_Failed,
};

@class TSThread;

@interface OWSBackup : NSObject

@property (nonatomic, readonly) OWSBackupState backupExportState;

//@property (nonatomic, readonly) CGFloat backupProgress;
//
//// If non-nil, backup is encrypted.
//@property (nonatomic, nullable, readonly) NSString *backupPassword;
//
//// Only applies to "backup export" task.
//@property (nonatomic, nullable, readonly) TSThread *currentThread;
//
//@property (nonatomic, readonly) NSString *backupZipPath;
//

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (BOOL)isBackupEnabled;
- (void)setIsBackupEnabled:(BOOL)value;

//- (void)exportBackup:(nullable TSThread *)currentThread skipPassword:(BOOL)skipPassword;
//
//- (void)importBackup:(NSString *)backupZipPath password:(NSString *_Nullable)password;
//
//- (void)cancel;
//
//+ (void)applicationDidFinishLaunching;

@end

NS_ASSUME_NONNULL_END
