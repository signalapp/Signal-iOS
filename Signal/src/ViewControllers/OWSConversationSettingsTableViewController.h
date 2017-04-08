//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSConversationSettingsTableViewController : OWSTableViewController

- (void)configureWithThread:(TSThread *)thread;
- (void)presentedModalWasDismissed;

@end

NS_ASSUME_NONNULL_END
