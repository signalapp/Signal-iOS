//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
};

@class ConversationViewCell;
@class TSThread;
@class ThreadViewModel;

@protocol ConversationViewItem;

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) TSThread *thread;
@property (nonatomic, readonly) ThreadViewModel *threadViewModel;
@property (nonatomic, readonly) BOOL isUserScrolling;
@property (nonatomic, readonly) CGFloat safeContentHeight;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId NS_DESIGNATED_INITIALIZER;

- (void)popKeyBoard;
- (void)dismissKeyBoard;

- (void)updateMessageActionsStateForCell:(ConversationViewCell *)cell;

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

@class ConversationCollectionView;
@class ConversationHeaderView;
@class ConversationSearchController;
@class ConversationStyle;
@class ConversationViewCell;
@class ConversationViewLayout;
@class ConversationViewModel;
@class MessageActionsToolbar;
@class SDSDatabaseStorage;
@class SelectionHighlightView;

@protocol ConversationViewItem;

typedef NS_CLOSED_ENUM(NSUInteger,
    ConversationUIMode) { ConversationUIMode_Normal, ConversationUIMode_Search, ConversationUIMode_Selection };

@interface ConversationViewController (Internal)

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewModel *conversationViewModel;
@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (nonatomic, readonly) BOOL isViewVisible;
@property (nonatomic, readonly) BOOL isPresentingMessageActions;
@property (nonatomic, readonly) ConversationHeaderView *headerView;

@property (nonatomic, readonly) ConversationStyle *conversationStyle;
@property (nonatomic, readonly) ConversationViewLayout *layout;

- (void)dismissMessageRequestView;
- (void)showDetailViewForViewItem:(id<ConversationViewItem>)conversationItem;
- (void)populateReplyForViewItem:(id<ConversationViewItem>)conversationItem;

@property (nonatomic) ConversationUIMode uiMode;
- (void)updateBarButtonItems;
- (void)reloadBottomBar;

#pragma mark - Search

@property (nonatomic, readonly) ConversationSearchController *searchController;

#pragma mark - Selection

@property (nonatomic, readonly) MessageActionsToolbar *selectionToolbar;
@property (nonatomic) NSDictionary<NSString *, id<ConversationViewItem>> *selectedItems;
@property (nonatomic, readonly) SelectionHighlightView *selectionHighlightView;

- (void)conversationCell:(nonnull ConversationViewCell *)cell didSelectViewItem:(id<ConversationViewItem>)viewItem;

@end

NS_ASSUME_NONNULL_END
