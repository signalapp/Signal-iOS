//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import <SignalMessaging/OWSViewController.h>
#import <UIKit/UIKit.h>

@class TSThread;

@interface HomeViewController : OWSViewController

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action;

- (void)showNewConversationView;

- (void)presentTopLevelModalViewController:(UIViewController *)viewController
                          animateDismissal:(BOOL)animateDismissal
                       animatePresentation:(BOOL)animatePresentation;
- (void)pushTopLevelViewController:(UIViewController *)viewController
                  animateDismissal:(BOOL)animateDismissal
               animatePresentation:(BOOL)animatePresentation;

@end
