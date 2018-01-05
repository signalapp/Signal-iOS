//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol OWSBackupDelegate <NSObject>

- (void)backupStateDidChange;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSBackupState) {
    OWSBackupState_InProgress,
    OWSBackupState_Cancelled,
    OWSBackupState_Complete,
};

@class TSThread;

@interface OWSBackup : NSObject

@property (nonatomic, weak) id<OWSBackupDelegate> delegate;

@property (nonatomic) OWSBackupState backupState;

// If non-nil, backup is encrypted.
@property (nonatomic, nullable, readonly) NSString *backupPassword;

@property (nonatomic, nullable, readonly) TSThread *currentThread;

@property (nonatomic, readonly) NSString *backupZipPath;

- (void)exportBackup:(nullable TSThread *)currentThread skipPassword:(BOOL)skipPassword;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
