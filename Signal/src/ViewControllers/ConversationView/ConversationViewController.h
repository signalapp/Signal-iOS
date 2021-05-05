//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
    ConversationViewActionGroupCallLobby,
    ConversationViewActionNewGroupActionSheet,
    ConversationViewActionUpdateDraft
};

@class CVLoadCoordinator;
@class CVViewState;
@class ConversationCollectionView;
@class ConversationHeaderView;
@class ConversationSearchController;
@class ConversationStyle;
@class ConversationViewLayout;
@class MessageActionsToolbar;
@class MessageBody;
@class SDSAnyReadTransaction;
@class SDSDatabaseStorage;
@class SignalAttachment;
@class TSMessage;
@class TSThread;
@class ThreadViewModel;

@protocol CVComponentDelegate;

@interface ConversationViewController : OWSViewController <CVComponentDelegate>

@property (nonatomic, readonly) CGFloat safeContentHeight;

@property (nonatomic, readonly) CVLoadCoordinator *loadCoordinator;
@property (nonatomic, nullable, readonly) NSArray<TSMessage *> *unreadMentionMessages;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId NS_DESIGNATED_INITIALIZER;

- (void)updateMessageActionsStateForCell:(UIView *)cell;

- (ConversationInputToolbar *)buildInputToolbar:(ConversationStyle *)conversationStyle
                                   messageDraft:(nullable MessageBody *)messageDraft
                                 voiceMemoDraft:(nullable VoiceMessageModel *)voiceMemoDraft
    NS_SWIFT_NAME(buildInputToolbar(conversationStyle:messageDraft:voiceMemoDraft:));

#pragma mark 3D Touch/UIContextMenu Methods

- (void)previewSetup;

#pragma mark - Keyboard Shortcuts

- (void)showConversationSettings;
- (void)focusInputToolbar;
- (void)openAllMedia;
- (void)openStickerKeyboard;
- (void)openAttachmentKeyboard;
- (void)openGifSearch;
- (void)dismissMessageActionsAnimated:(BOOL)animated;
- (void)dismissMessageActionsAnimated:(BOOL)animated completion:(void (^)(void))completion;

@property (nonatomic, readonly) BOOL isShowingSelectionUI;

@end

#pragma mark - Internal Methods. Used in extensions

typedef NS_CLOSED_ENUM(NSUInteger, ConversationUIMode) {
    ConversationUIMode_Normal,
    ConversationUIMode_Search,
    ConversationUIMode_Selection
};

@interface ConversationViewController (Internal)

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) BOOL isViewVisible;
@property (nonatomic, readonly) BOOL isPresentingMessageActions;
@property (nonatomic, readonly) ConversationHeaderView *headerView;

@property (nonatomic, readonly) ConversationViewLayout *layout;
@property (nonatomic, readonly) CVViewState *viewState;

- (void)tryToSendAttachments:(NSArray<SignalAttachment *> *)attachments
                 messageBody:(MessageBody *_Nullable)messageBody NS_SWIFT_NAME(tryToSendAttachments(_:messageBody:));

- (void)updateBarButtonItems;
- (void)ensureBannerState;

// TODO: Remove or rework method.
- (void)reloadCollectionViewForReset;

- (void)updateNavigationBarSubtitleLabel;
- (void)dismissMessageActionsIfNecessary;
- (void)reloadReactionsDetailSheetWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)updateNavigationTitle;
- (void)updateUnreadMessageFlagWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)updateUnreadMessageFlagUsingAsyncTransaction;
- (void)configureScrollDownButtons;
- (void)performBatchUpdates:(void (^_Nonnull)(void))batchUpdates
                 completion:(void (^_Nonnull)(BOOL))completion
            logFailureBlock:(void (^_Nonnull)(void))logFailureBlock
       shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
             isLoadAdjacent:(BOOL)isLoadAdjacent;
- (BOOL)autoLoadMoreIfNecessary;

#pragma mark - Search

@property (nonatomic, readonly) ConversationSearchController *searchController;

#pragma mark - Selection

@property (nonatomic, readonly) MessageActionsToolbar *selectionToolbar;

@property (nonatomic, readonly) id<CVComponentDelegate> componentDelegate;

@end

NS_ASSUME_NONNULL_END
