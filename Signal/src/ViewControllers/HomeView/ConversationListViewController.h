//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import <SignalMessaging/OWSViewController.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ConversationListViewControllerSection) {
    ConversationListViewControllerSectionReminders,
    ConversationListViewControllerSectionPinned,
    ConversationListViewControllerSectionUnpinned,
    ConversationListViewControllerSectionArchiveButton,
};

@class TSThread;

@interface ConversationListViewController : OWSViewController

- (void)presentThread:(TSThread *)thread action:(ConversationViewAction)action animated:(BOOL)isAnimated;

- (void)presentThread:(TSThread *)thread
               action:(ConversationViewAction)action
       focusMessageId:(nullable NSString *)focusMessageId
             animated:(BOOL)isAnimated;

// Used by force-touch Springboard icon shortcut and key commands
- (void)showNewConversationView;
- (void)showNewGroupView;
- (void)focusSearch;
- (void)selectPreviousConversation;
- (void)selectNextConversation;
- (void)archiveSelectedConversation;
- (void)unarchiveSelectedConversation;

@property (nonatomic) TSThread *lastViewedThread;

// For use by Swift extension.
- (void)updateBarButtonItems;
- (void)updateReminderViews;
- (void)updateViewState;
- (void)updateShouldObserveDBModifications;
- (void)reloadTableViewData;
- (void)updateFirstConversationLabel;
- (void)presentGetStartedBannerIfNecessary;
- (void)updateAvatars;
- (void)resetMappings;
- (void)updateUnreadPaymentNotificationsCountWithSneakyTransaction;
- (void)anyUIDBDidUpdateWithUpdatedThreadIds:(NSSet<NSString *> *)updatedItemIds;

@property (nonatomic) BOOL shouldObserveDBModifications;
@property (nonatomic) UIView *firstConversationCueView;

@end

NS_ASSUME_NONNULL_END
