//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSBackupImportViewController : OWSViewController

- (void)importBackup:(NSString *)backupZipPath password:(NSString *_Nullable)password;

@end

NS_ASSUME_NONNULL_END
