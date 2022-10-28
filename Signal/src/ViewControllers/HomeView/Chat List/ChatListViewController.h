//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "ConversationViewController.h"
#import <SignalUI/OWSViewControllerObjc.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CLVViewState;
@class TSThread;

@interface ChatListViewController : OWSViewControllerObjc

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated;

- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId
             animated:(BOOL)isAnimated;

// Used by force-touch Springboard icon shortcut and key commands
- (void)showNewConversationView;
- (void)showNewGroupView;
- (void)focusSearch;
- (void)archiveSelectedConversation;
- (void)unarchiveSelectedConversation;

@property (nonatomic, readonly) CLVViewState *viewState;

/// Used to update the selected cell for split view and maintain scroll positions for reappearing collapsed views.
- (void)updateLastViewedThread:(TSThread *)thread animated:(BOOL)animated;

// For use by Swift extension.
- (void)updateBarButtonItems;
- (void)updateViewState;
- (void)presentGetStartedBannerIfNecessary;

@property (nonatomic) UILabel *firstConversationLabel;
@property (nonatomic) UIView *firstConversationCueView;
@property (nonatomic) BOOL hasShownBadgeExpiration;

@end

NS_ASSUME_NONNULL_END
