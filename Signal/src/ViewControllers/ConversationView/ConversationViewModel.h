//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class ConversationViewModel;
@class OWSQuotedReplyModel;
@class TSOutgoingMessage;
@class TSThread;
@class ThreadDynamicInteractions;

@protocol ConversationViewItem;

typedef NS_ENUM(NSUInteger, ConversationUpdateType) {
    // No view items in the load window were effected.
    ConversationUpdateType_Minor,
    // A subset of view items in the load window were effected;
    // the view should be updated using the update items.
    ConversationUpdateType_Diff,
    // Complicated or unexpected changes occurred in the load window;
    // the view should be reloaded.
    ConversationUpdateType_Reload,
};

#pragma mark -

typedef NS_ENUM(NSUInteger, ConversationUpdateItemType) {
    ConversationUpdateItemType_Insert,
    ConversationUpdateItemType_Delete,
    ConversationUpdateItemType_Update,
};

#pragma mark -

@interface ConversationUpdateItem : NSObject

@property (nonatomic, readonly) ConversationUpdateItemType updateItemType;
// Only applies in the "delete" and "update" cases.
@property (nonatomic, readonly) NSUInteger oldIndex;
// Only applies in the "insert" and "update" cases.
@property (nonatomic, readonly) NSUInteger newIndex;
// Only applies in the "insert" and "update" cases.
@property (nonatomic, readonly, nullable) id<ConversationViewItem> viewItem;

@end

#pragma mark -

@interface ConversationUpdate : NSObject

@property (nonatomic, readonly) ConversationUpdateType conversationUpdateType;
// Only applies in the "diff" case.
@property (nonatomic, readonly, nullable) NSArray<ConversationUpdateItem *> *updateItems;
//// Only applies in the "diff" case.
@property (nonatomic, readonly) BOOL shouldAnimateUpdates;

@end

#pragma mark -

@protocol ConversationViewModelDelegate <NSObject>

- (void)conversationViewModelWillUpdate;
- (void)conversationViewModelDidUpdate:(ConversationUpdate *)conversationUpdate;

- (void)conversationViewModelWillLoadMoreItems;
- (void)conversationViewModelDidLoadMoreItems;
- (void)conversationViewModelDidLoadPrevPage;
- (void)conversationViewModelRangeDidChange;

// Called after the view model recovers from a severe error
// to prod the view to reset its scroll state, etc.
- (void)conversationViewModelDidReset;

- (void)conversationViewModelDidDeleteMostRecentMenuActionsViewItem;

- (BOOL)isObservingVMUpdates;

- (ConversationStyle *)conversationStyle;

@end

#pragma mark -

@interface ConversationViewModel : NSObject

@property (nonatomic, readonly) NSArray<id<ConversationViewItem>> *viewItems;
@property (nonatomic, nullable) NSString *focusMessageIdOnOpen;
@property (nonatomic, readonly, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic, nullable) id<ConversationViewItem> mostRecentMenuActionsViewItem;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread
          focusMessageIdOnOpen:(nullable NSString *)focusMessageIdOnOpen
                      delegate:(id<ConversationViewModelDelegate>)delegate NS_DESIGNATED_INITIALIZER;

- (void)ensureDynamicInteractionsAndUpdateIfNecessary:(BOOL)updateIfNecessary;

- (void)clearUnreadMessagesIndicator;

- (void)loadAnotherPageOfMessages;

- (void)viewDidResetContentAndLayout;

- (void)viewDidLoad;

- (BOOL)canLoadMoreItems;

- (nullable NSIndexPath *)ensureLoadWindowContainsQuotedReply:(OWSQuotedReplyModel *)quotedReply;
- (nullable NSIndexPath *)ensureLoadWindowContainsInteractionId:(NSString *)interactionId;

- (void)appendUnsavedOutgoingTextMessage:(TSOutgoingMessage *)outgoingMessage;

@end

NS_ASSUME_NONNULL_END
