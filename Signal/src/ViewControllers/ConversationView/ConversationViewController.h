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

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) CGFloat safeContentHeight;

@property (nonatomic, readonly) CVLoadCoordinator *loadCoordinator;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId NS_DESIGNATED_INITIALIZER;

#pragma mark - Keyboard Shortcuts

- (void)focusInputToolbar;
- (void)openAllMedia;
- (void)openStickerKeyboard;
- (void)openAttachmentKeyboard;
- (void)openGifSearch;

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
@property (nonatomic, readonly) ConversationHeaderView *headerView;

@property (nonatomic, readonly) ConversationViewLayout *layout;
@property (nonatomic, readonly) CVViewState *viewState;

// TODO: Remove or rework method.
- (void)reloadCollectionViewForReset;

- (void)reloadReactionsDetailSheetWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)performBatchUpdates:(void (^_Nonnull)(void))batchUpdates
                 completion:(void (^_Nonnull)(BOOL))completion
            logFailureBlock:(void (^_Nonnull)(void))logFailureBlock
       shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
             isLoadAdjacent:(BOOL)isLoadAdjacent;

#pragma mark - Search

@property (nonatomic, readonly) ConversationSearchController *searchController;

#pragma mark - Selection

@property (nonatomic, readonly) MessageActionsToolbar *selectionToolbar;

@end

NS_ASSUME_NONNULL_END
