//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import <RelayMessaging/OWSViewController.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface HomeViewController : OWSViewController

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action;
- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId;

- (void)showNewConversationView;

- (void)presentTopLevelModalViewController:(UIViewController *)viewController
                          animateDismissal:(BOOL)animateDismissal
                       animatePresentation:(BOOL)animatePresentation;
- (void)pushTopLevelViewController:(UIViewController *)viewController
                  animateDismissal:(BOOL)animateDismissal
               animatePresentation:(BOOL)animatePresentation;

@end

NS_ASSUME_NONNULL_END
