//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import <SignalUI/OWSViewController.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CLVViewState;
@class TSThread;

@interface ChatListViewController : OWSViewController

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
@property (nonatomic) TSThread *lastViewedThread;

// For use by Swift extension.
- (void)updateBarButtonItems;
- (void)updateViewState;
- (void)presentGetStartedBannerIfNecessary;

@property (nonatomic) UILabel *firstConversationLabel;
@property (nonatomic) UIView *firstConversationCueView;
@property (nonatomic) BOOL hasShownBadgeExpiration;

@end

NS_ASSUME_NONNULL_END
