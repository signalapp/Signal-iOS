//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import "OWSTableViewController.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSConversationSettingsViewController : OWSTableViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> conversationSettingsViewDelegate;

@property (nonatomic) BOOL showVerificationOnAppear;

- (void)configureWithThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
