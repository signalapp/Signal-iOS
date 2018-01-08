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

@interface OWSBackup : NSObject

@property (nonatomic, weak) id<OWSBackupDelegate> delegate;

@property (nonatomic, readonly) OWSBackupState backupState;

@property (nonatomic, readonly) CGFloat backupProgress;

// If non-nil, backup is encrypted.
@property (nonatomic, nullable, readonly) NSString *backupPassword;

@property (nonatomic, nullable, readonly) TSThread *currentThread;

@property (nonatomic, readonly) NSString *backupZipPath;

- (void)exportBackup:(nullable TSThread *)currentThread skipPassword:(BOOL)skipPassword;

- (void)importBackup:(NSString *)backupZipPath password:(NSString *_Nullable)password;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
