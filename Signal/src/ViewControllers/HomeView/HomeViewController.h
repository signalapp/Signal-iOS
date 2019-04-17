//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import <SignalMessaging/OWSViewController.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HomeViewControllerSection) {
    HomeViewControllerSectionReminders,
    HomeViewControllerSectionConversations,
    HomeViewControllerSectionArchiveButton,
};

@class TSThread;

@interface HomeViewController : OWSViewController

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated;

- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId
             animated:(BOOL)isAnimated;

// Used by force-touch Springboard icon shortcut
- (void)showNewConversationView;

@end

NS_ASSUME_NONNULL_END
