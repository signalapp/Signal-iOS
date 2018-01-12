//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSBackupExportViewController : OWSViewController

// If currentThread is non-nil, we should offer to let users send the
// backup in that thread.
- (void)exportBackup:(TSThread *_Nullable)currentThread skipPassword:(BOOL)skipPassword;

@end

NS_ASSUME_NONNULL_END
