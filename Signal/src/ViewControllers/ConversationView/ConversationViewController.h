//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
    ConversationViewActionGroupCallLobby
};

@class CVCViewState;
@class ConversationCollectionView;
@class ConversationHeaderView;
@class ConversationSearchController;
@class ConversationViewCell;
@class ConversationViewLayout;
@class ConversationViewModel;
@class MessageActionsToolbar;
@class SDSDatabaseStorage;
@class SelectionHighlightView;
@class TSThread;
@class ThreadViewModel;

@protocol ConversationViewItem;
@protocol ConversationViewItem;

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) TSThread *thread;
@property (nonatomic, readonly) ThreadViewModel *threadViewModel;
@property (nonatomic, readonly) BOOL isUserScrolling;
@property (nonatomic, readonly) CGFloat safeContentHeight;
@property (nonatomic, nullable) NSString *panGestureCurrentInteractionId;
@property (nonatomic, nullable) NSString *longPressGestureCurrentInteractionId;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId NS_DESIGNATED_INITIALIZER;

- (void)updateMessageActionsStateForCell:(ConversationViewCell *)cell;

- (ConversationInputToolbar *)buildInputToolbar:(ConversationStyle *)conversationStyle
    NS_SWIFT_NAME(buildInputToolbar(conversationStyle:));

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

#pragma mark - Keyboard Shortcuts

- (void)showConversationSettings;
- (void)focusInputToolbar;
- (void)openAllMedia;
- (void)openStickerKeyboard;
- (void)openAttachmentKeyboard;
- (void)openGifSearch;
- (void)dismissMessageActionsAnimated:(BOOL)animated;
- (void)dismissMessageActionsAnimated:(BOOL)animated completion:(void (^)(void))completion;

@end

#pragma mark - Internal Methods. Used in extensions

typedef NS_CLOSED_ENUM(NSUInteger,
    ConversationUIMode) { ConversationUIMode_Normal, ConversationUIMode_Search, ConversationUIMode_Selection };

@interface ConversationViewController (Internal)

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewModel *conversationViewModel;
@property (nonatomic, readonly) BOOL isViewVisible;
@property (nonatomic, readonly) BOOL isPresentingMessageActions;
@property (nonatomic, readonly) ConversationHeaderView *headerView;

@property (nonatomic, readonly) ConversationViewLayout *layout;
@property (nonatomic, readonly) CVCViewState *viewState;

@property (nonatomic) ConversationUIMode uiMode;

- (void)showDetailViewForViewItem:(id<ConversationViewItem>)conversationItem;
- (void)populateReplyForViewItem:(id<ConversationViewItem>)conversationItem;
- (void)updateBarButtonItems;
- (void)ensureBannerState;
- (void)updateContentInsetsAnimated:(BOOL)animated;

#pragma mark - Search

@property (nonatomic, readonly) ConversationSearchController *searchController;

#pragma mark - Selection

@property (nonatomic, readonly) MessageActionsToolbar *selectionToolbar;
@property (nonatomic) NSDictionary<NSString *, id<ConversationViewItem>> *selectedItems;
@property (nonatomic, readonly) SelectionHighlightView *selectionHighlightView;
@property (nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic, readonly) UILongPressGestureRecognizer *longPressGestureRecognizer;
@property (nonatomic, readonly) BOOL isShowingSelectionUI;

- (void)conversationCell:(nonnull ConversationViewCell *)cell didSelectViewItem:(id<ConversationViewItem>)viewItem;

@end

NS_ASSUME_NONNULL_END
