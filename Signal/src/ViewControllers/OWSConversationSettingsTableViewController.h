//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import "OWSTableViewController.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSConversationSettingsTableViewController : OWSTableViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> delegate;

- (void)configureWithThread:(TSThread *)thread;
- (void)presentedModalWasDismissed;

@end

NS_ASSUME_NONNULL_END
