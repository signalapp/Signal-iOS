//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
- (void)showAppSettings;
- (void)focusSearch;
- (void)selectPreviousConversation;
- (void)selectNextConversation;
- (void)archiveSelectedConversation;
- (void)unarchiveSelectedConversation;

@property (nonatomic) TSThread *lastViewedThread;

@end

NS_ASSUME_NONNULL_END
