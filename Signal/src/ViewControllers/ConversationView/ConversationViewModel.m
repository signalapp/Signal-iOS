//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewModel.h"
#import "ConversationViewItem.h"
#import "DateUtil.h"
#import "OWSMessageBubbleView.h"
#import "OWSQuotedReplyModel.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMessaging/OWSContactOffersInteraction.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSUnreadIndicator.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewChangePrivate.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationProfileState : NSObject

@property (nonatomic) BOOL hasLocalProfile;
@property (nonatomic) BOOL isThreadInProfileWhitelist;
@property (nonatomic) BOOL hasUnwhitelistedMember;

@end

#pragma mark -

@implementation ConversationProfileState

@end

#pragma mark -

@implementation ConversationUpdateItem

- (instancetype)initWithUpdateItemType:(ConversationUpdateItemType)updateItemType
                              oldIndex:(NSUInteger)oldIndex
                              newIndex:(NSUInteger)newIndex
                              viewItem:(nullable id<ConversationViewItem>)viewItem
{
    self = [super init];
    if (!self) {
        return self;
    }

    _updateItemType = updateItemType;
    _oldIndex = oldIndex;
    _newIndex = newIndex;
    _viewItem = viewItem;

    return self;
}

@end

#pragma mark -

@implementation ConversationUpdate

- (instancetype)initWithConversationUpdateType:(ConversationUpdateType)conversationUpdateType
                                   updateItems:(nullable NSArray<ConversationUpdateItem *> *)updateItems
                          shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
{
    self = [super init];
    if (!self) {
        return self;
    }

    _conversationUpdateType = conversationUpdateType;
    _updateItems = updateItems;
    _shouldAnimateUpdates = shouldAnimateUpdates;

    return self;
}

+ (ConversationUpdate *)minorUpdate
{
    return [[ConversationUpdate alloc] initWithConversationUpdateType:ConversationUpdateType_Minor
                                                          updateItems:nil
                                                 shouldAnimateUpdates:NO];
}

+ (ConversationUpdate *)reloadUpdate
{
    return [[ConversationUpdate alloc] initWithConversationUpdateType:ConversationUpdateType_Reload
                                                          updateItems:nil
                                                 shouldAnimateUpdates:NO];
}

+ (ConversationUpdate *)diffUpdateWithUpdateItems:(nullable NSArray<ConversationUpdateItem *> *)updateItems
                             shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
{
    return [[ConversationUpdate alloc] initWithConversationUpdateType:ConversationUpdateType_Diff
                                                          updateItems:updateItems
                                                 shouldAnimateUpdates:shouldAnimateUpdates];
}

@end

#pragma mark -

// Always load up to n messages when user arrives.
//
// The smaller this number is, the faster the conversation can display.
// To test, shrink you accessability font as much as possible, then count how many 1-line system info messages (our
// shortest cells) can fit on screen at a time on an iPhoneX
//
// PERF: we could do less messages on shorter (older, slower) devices
// PERF: we could cache the cell height, since some messages will be much taller.
static const int kYapDatabasePageSize = 18;

// Never show more than n messages in conversation view when user arrives.
static const int kConversationInitialMaxRangeSize = 300;

// Never show more than n messages in conversation view at a time.
static const int kYapDatabaseRangeMaxLength = 25000;

#pragma mark -

@interface ConversationViewModel ()

@property (nonatomic, weak) id<ConversationViewModelDelegate> delegate;

@property (nonatomic, readonly) TSThread *thread;

// The mapping must be updated in lockstep with the uiDatabaseConnection.
//
// * The first (required) step is to update uiDatabaseConnection using beginLongLivedReadTransaction.
// * The second (required) step is to update messageMapping. The desired length of the mapping
//   can be modified at this time.
// * The third (optional) step is to update the view items using reloadViewItems.
// * The steps must be done in strict order.
// * If we do any of the steps, we must do all of the required steps.
// * We can't use messageMapping or viewItems after the first step until we've
//   done the last step; i.e.. we can't do any layout, since that uses the view
//   items which haven't been updated yet.
// * Afterward, we must prod the view controller to update layout & view state.
@property (nonatomic) ConversationMessageMapping *messageMapping;

@property (nonatomic) NSArray<id<ConversationViewItem>> *viewItems;
@property (nonatomic) NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache;

@property (nonatomic, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic, nullable) NSDate *collapseCutoffDate;
@property (nonatomic, nullable) NSString *typingIndicatorsSender;

@property (nonatomic, nullable) ConversationProfileState *conversationProfileState;
@property (nonatomic) BOOL hasTooManyOutgoingMessagesToBlockCached;

@property (nonatomic) NSArray<id<ConversationViewItem>> *persistedViewItems;
@property (nonatomic) NSArray<TSOutgoingMessage *> *unsavedOutgoingMessages;

@end

#pragma mark -

@implementation ConversationViewModel

- (instancetype)initWithThread:(TSThread *)thread
          focusMessageIdOnOpen:(nullable NSString *)focusMessageIdOnOpen
                      delegate:(id<ConversationViewModelDelegate>)delegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(thread);
    OWSAssertDebug(delegate);

    _thread = thread;
    _delegate = delegate;
    _persistedViewItems = @[];
    _unsavedOutgoingMessages = @[];
    self.focusMessageIdOnOpen = focusMessageIdOnOpen;

    [self configure];

    return self;
}

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

- (YapDatabaseConnection *)uiDatabaseConnection
{
    return self.primaryStorage.uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    return self.primaryStorage.dbReadWriteConnection;
}

- (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

- (OWSBlockingManager *)blockingManager
{
    return OWSBlockingManager.sharedManager;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

#pragma mark -

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(typingIndicatorStateDidChange:)
                                                 name:[OWSTypingIndicatorsImpl typingIndicatorStateDidChange]
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationName_ProfileWhitelistDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationName_BlockListDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localProfileDidChange:)
                                                 name:kNSNotificationName_LocalProfileDidChange
                                               object:nil];
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ensureDynamicInteractionsAndUpdateIfNecessary:YES];
}

- (void)profileWhitelistDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.conversationProfileState = nil;
    [self updateForTransientItems];
}

- (void)localProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.conversationProfileState = nil;
    [self updateForTransientItems];
}

- (void)blockListDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self updateForTransientItems];
}

- (void)configure
{
    OWSLogInfo(@"");

    // We need to update the "unread indicator" _before_ we determine the initial range
    // size, since it depends on where the unread indicator is placed.
    self.typingIndicatorsSender = [self.typingIndicators typingRecipientIdForThread:self.thread];
    self.collapseCutoffDate = [NSDate new];

    [self ensureDynamicInteractionsAndUpdateIfNecessary:NO];
    [self.primaryStorage updateUIDatabaseConnectionToLatest];

    [self createNewMessageMapping];
    if (![self reloadViewItems]) {
        OWSFailDebug(@"failed to reload view items in configureForThread.");
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(uiDatabaseDidUpdateExternally:)
                                                 name:OWSUIDatabaseConnectionDidUpdateExternallyNotification
                                               object:self.primaryStorage.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(uiDatabaseWillUpdate:)
                                                 name:OWSUIDatabaseConnectionWillUpdateNotification
                                               object:self.primaryStorage.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(uiDatabaseDidUpdate:)
                                                 name:OWSUIDatabaseConnectionDidUpdateNotification
                                               object:self.primaryStorage.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)viewDidLoad
{
    [self addNotificationListeners];

    [self touchDbAsync];
}

- (void)touchDbAsync
{
    // See comments in primaryStorage.touchDbAsync.
    [self.primaryStorage touchDbAsync];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)canLoadMoreItems
{
    if (self.messageMapping.desiredLength >= kYapDatabaseRangeMaxLength) {
        return NO;
    }

    return self.messageMapping.canLoadMore;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    if (self.hasClearedUnreadMessagesIndicator) {
        self.hasClearedUnreadMessagesIndicator = NO;
        [self.dynamicInteractions clearUnreadIndicatorState];
    }
}

- (void)viewDidResetContentAndLayout
{
    self.collapseCutoffDate = [NSDate new];
    if (![self reloadViewItems]) {
        OWSFailDebug(@"failed to reload view items in resetContentAndLayout.");
    }
}

- (void)loadAnotherPageOfMessages
{
    BOOL hasEarlierUnseenMessages = self.dynamicInteractions.unreadIndicator.hasMoreUnseenMessages;

    // Now that we're using a "minimal" page size, we should
    // increase the load window by 2 pages at a time.
    [self loadNMoreMessages:kYapDatabasePageSize * 2];

    // Don’t auto-scroll after “loading more messages” unless we have “more unseen messages”.
    //
    // Otherwise, tapping on "load more messages" autoscrolls you downward which is completely wrong.
    if (hasEarlierUnseenMessages && !self.focusMessageIdOnOpen) {
        // Ensure view items are updated before trying to scroll to the
        // unread indicator.
        //
        // loadNMoreMessages calls resetMapping which calls ensureDynamicInteractions,
        // which may move the unread indicator, and for scrollToUnreadIndicatorAnimated
        // to work properly, the view items need to be updated to reflect that change.
        [self.primaryStorage updateUIDatabaseConnectionToLatest];

        [self.delegate conversationViewModelDidLoadPrevPage];
    }
}

- (void)loadNMoreMessages:(NSUInteger)numberOfMessagesToLoad
{
    [self.delegate conversationViewModelWillLoadMoreItems];

    [self resetMappingWithAdditionalLength:numberOfMessagesToLoad];

    [self.delegate conversationViewModelDidLoadMoreItems];
}

- (NSUInteger)initialMessageMappingLength
{
    NSUInteger rangeLength = kYapDatabasePageSize;

    // If this is the first time we're configuring the range length,
    // try to take into account the position of the unread indicator
    // and the "focus message".
    OWSAssertDebug(self.dynamicInteractions);

    if (self.focusMessageIdOnOpen) {
        OWSAssertDebug(self.dynamicInteractions.focusMessagePosition);
        if (self.dynamicInteractions.focusMessagePosition) {
            OWSLogVerbose(@"ensuring load of focus message: %@", self.dynamicInteractions.focusMessagePosition);
            rangeLength = MAX(rangeLength, 1 + self.dynamicInteractions.focusMessagePosition.unsignedIntegerValue);
        }
    }

    if (self.dynamicInteractions.unreadIndicator) {
        NSUInteger unreadIndicatorPosition
            = (NSUInteger)self.dynamicInteractions.unreadIndicator.unreadIndicatorPosition;

        // If there is an unread indicator, increase the initial load window
        // to include it.
        OWSAssertDebug(unreadIndicatorPosition > 0);
        OWSAssertDebug(unreadIndicatorPosition <= kYapDatabaseRangeMaxLength);

        // We'd like to include at least N seen messages,
        // to give the user the context of where they left off the conversation.
        const NSUInteger kPreferredSeenMessageCount = 1;
        rangeLength = MAX(rangeLength, unreadIndicatorPosition + kPreferredSeenMessageCount);
    }

    return rangeLength;
}

- (void)updateMessageMappingWithAdditionalLength:(NSUInteger)additionalLength
{
    // Range size should monotonically increase.
    NSUInteger rangeLength = self.messageMapping.desiredLength + additionalLength;

    // Always try to load at least a single page of messages.
    rangeLength = MAX(rangeLength, kYapDatabasePageSize);

    // Enforce max range size.
    rangeLength = MIN(rangeLength, kYapDatabaseRangeMaxLength);

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMapping updateWithDesiredLength:rangeLength transaction:transaction];
    }];

    [self.delegate conversationViewModelRangeDidChange];
    self.collapseCutoffDate = [NSDate new];
}

- (void)ensureDynamicInteractionsAndUpdateIfNecessary:(BOOL)updateIfNecessary
{
    OWSAssertIsOnMainThread();

    const int currentMaxRangeSize = (int)self.messageMapping.desiredLength;
    const int maxRangeSize = MAX(kConversationInitialMaxRangeSize, currentMaxRangeSize);

    ThreadDynamicInteractions *dynamicInteractions =
        [ThreadUtil ensureDynamicInteractionsForThread:self.thread
                                       contactsManager:self.contactsManager
                                       blockingManager:self.blockingManager
                                          dbConnection:self.editingDatabaseConnection
                           hideUnreadMessagesIndicator:self.hasClearedUnreadMessagesIndicator
                                   lastUnreadIndicator:self.dynamicInteractions.unreadIndicator
                                        focusMessageId:self.focusMessageIdOnOpen
                                          maxRangeSize:maxRangeSize];
    BOOL didChange = ![NSObject isNullableObject:self.dynamicInteractions equalTo:dynamicInteractions];
    self.dynamicInteractions = dynamicInteractions;

    if (didChange && updateIfNecessary) {
        if (![self reloadViewItems]) {
            OWSFailDebug(@"Failed to reload view items.");
        }

        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
    }
}

- (nullable id<ConversationViewItem>)viewItemForUnreadMessagesIndicator
{
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        if (viewItem.unreadIndicator) {
            return viewItem;
        }
    }
    return nil;
}

- (void)clearUnreadMessagesIndicator
{
    OWSAssertIsOnMainThread();

    // TODO: Remove by making unread indicator a view model concern.
    id<ConversationViewItem> _Nullable oldIndicatorItem = [self viewItemForUnreadMessagesIndicator];
    if (oldIndicatorItem) {
        // TODO ideally this would be happening within the *same* transaction that caused the unreadMessageIndicator
        // to be cleared.
        [self.editingDatabaseConnection
            asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [oldIndicatorItem.interaction touchWithTransaction:transaction];
            }];
    }

    if (self.hasClearedUnreadMessagesIndicator) {
        // ensureDynamicInteractionsForThread is somewhat expensive
        // so we don't want to call it unnecessarily.
        return;
    }

    // Once we've cleared the unread messages indicator,
    // make sure we don't show it again.
    self.hasClearedUnreadMessagesIndicator = YES;

    if (self.dynamicInteractions.unreadIndicator) {
        // If we've just cleared the "unread messages" indicator,
        // update the dynamic interactions.
        [self ensureDynamicInteractionsAndUpdateIfNecessary:YES];
    }
}

#pragma mark - Storage access

- (void)uiDatabaseDidUpdateExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    if (!self.delegate.isObservingVMUpdates) {
        return;
    }

    // External database modifications (e.g. changes from another process such as the SAE)
    // are "flushed" using touchDbAsync when the app re-enters the foreground.
}

- (void)uiDatabaseWillUpdate:(NSNotification *)notification
{
    if (!self.delegate.isObservingVMUpdates) {
        return;
    }
    [self.delegate conversationViewModelWillUpdate];
}

- (void)uiDatabaseDidUpdate:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    NSArray<NSNotification *> *notifications = notification.userInfo[OWSUIDatabaseConnectionNotificationsKey];
    OWSAssertDebug([notifications isKindOfClass:[NSArray class]]);

    YapDatabaseAutoViewConnection *messageDatabaseView =
        [self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName];
    OWSAssertDebug([messageDatabaseView isKindOfClass:[YapDatabaseAutoViewConnection class]]);
    if (![messageDatabaseView hasChangesForGroup:self.thread.uniqueId inNotifications:notifications]) {
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate];
        return;
    }

    __block ConversationMessageMappingDiff *_Nullable diff = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        diff = [self.messageMapping updateAndCalculateDiffWithTransaction:transaction notifications:notifications];
    }];
    if (!diff) {
        OWSFailDebug(@"Could not determine diff");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMapping];
        [self.delegate conversationViewModelDidReset];
        return;
    }
    if (diff.addedItemIds.count < 1 && diff.removedItemIds.count < 1 && diff.updatedItemIds.count < 1) {
        // This probably isn't an error; presumably the modifications
        // occurred outside the load window.
        OWSLogDebug(@"Empty diff.");
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate];
        return;
    }

    NSString *_Nullable mostRecentMenuActionsInterationId = self.mostRecentMenuActionsViewItem.interaction.uniqueId;
    if (mostRecentMenuActionsInterationId != nil &&
        [diff.removedItemIds containsObject:mostRecentMenuActionsInterationId]) {
        [self.delegate conversationViewModelDidDeleteMostRecentMenuActionsViewItem];
    }

    NSMutableSet<NSString *> *diffAddedItemIds = [diff.addedItemIds mutableCopy];
    NSMutableSet<NSString *> *diffRemovedItemIds = [diff.removedItemIds mutableCopy];
    NSMutableSet<NSString *> *diffUpdatedItemIds = [diff.updatedItemIds mutableCopy];
    for (TSOutgoingMessage *unsavedOutgoingMessage in self.unsavedOutgoingMessages) {
        // unsavedOutgoingMessages should only exist for a short period (usually 30-50ms) before
        // they are saved and moved into the `persistedViewItems`
        OWSAssertDebug(unsavedOutgoingMessage.timestamp >= ([NSDate ows_millisecondTimeStamp] - 1 * kSecondInMs));

        BOOL isFound = ([diff.addedItemIds containsObject:unsavedOutgoingMessage.uniqueId] ||
            [diff.removedItemIds containsObject:unsavedOutgoingMessage.uniqueId] ||
            [diff.updatedItemIds containsObject:unsavedOutgoingMessage.uniqueId]);
        if (isFound) {
            // Convert the "insert" to an "update".
            if ([diffAddedItemIds containsObject:unsavedOutgoingMessage.uniqueId]) {
                OWSLogVerbose(@"Converting insert to update: %@", unsavedOutgoingMessage.uniqueId);
                [diffAddedItemIds removeObject:unsavedOutgoingMessage.uniqueId];
                [diffUpdatedItemIds addObject:unsavedOutgoingMessage.uniqueId];
            }

            // Remove the unsavedOutgoingViewItem since it now exists as a persistedViewItem
            NSMutableArray<TSOutgoingMessage *> *unsavedOutgoingMessages = [self.unsavedOutgoingMessages mutableCopy];
            [unsavedOutgoingMessages removeObject:unsavedOutgoingMessage];
            self.unsavedOutgoingMessages = [unsavedOutgoingMessages copy];
        }
    }

    NSMutableArray<NSString *> *oldItemIdList = [NSMutableArray new];
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [oldItemIdList addObject:viewItem.itemId];
    }

    // We need to reload any modified interactions _before_ we call
    // reloadViewItems.
    BOOL hasMalformedRowChange = NO;
    NSMutableSet<NSString *> *updatedItemSet = [NSMutableSet new];
    for (NSString *uniqueId in diffUpdatedItemIds) {
        id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[uniqueId];
        if (viewItem) {
            [self reloadInteractionForViewItem:viewItem];
            [updatedItemSet addObject:viewItem.itemId];
        } else {
            OWSFailDebug(@"Update is missing view item");
            hasMalformedRowChange = YES;
        }
    }
    for (NSString *uniqueId in diffRemovedItemIds) {
        [self.viewItemCache removeObjectForKey:uniqueId];
    }

    if (hasMalformedRowChange) {
        // These errors seems to be very rare; they can only be reproduced
        // using the more extreme actions in the debug UI.
        OWSFailDebug(@"hasMalformedRowChange");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMapping];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    if (![self reloadViewItems]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mapping.");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMapping];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewItems.count);

    [self updateViewWithOldItemIdList:oldItemIdList updatedItemSet:updatedItemSet];
}

// A simpler version of the update logic we use when
// only transient items have changed.
- (void)updateForTransientItems
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    NSMutableArray<NSString *> *oldItemIdList = [NSMutableArray new];
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [oldItemIdList addObject:viewItem.itemId];
    }

    if (![self reloadViewItems]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mapping.");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMapping];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewItems.count);

    [self updateViewWithOldItemIdList:oldItemIdList updatedItemSet:[NSSet set]];
}

- (void)updateViewWithOldItemIdList:(NSArray<NSString *> *)oldItemIdList
                     updatedItemSet:(NSSet<NSString *> *)updatedItemSetParam {
    OWSAssertDebug(oldItemIdList);
    OWSAssertDebug(updatedItemSetParam);

    if (!self.delegate.isObservingVMUpdates) {
        OWSLogVerbose(@"Skipping VM update.");
        // We fire this event, but it will be ignored.
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate];
        return;
    }

    if (oldItemIdList.count != [NSSet setWithArray:oldItemIdList].count) {
        OWSFailDebug(@"Old view item list has duplicates.");
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        return;
    }

    NSMutableArray<NSString *> *newItemIdList = [NSMutableArray new];
    NSMutableDictionary<NSString *, id<ConversationViewItem>> *newViewItemMap = [NSMutableDictionary new];
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [newItemIdList addObject:viewItem.itemId];
        newViewItemMap[viewItem.itemId] = viewItem;
    }

    if (newItemIdList.count != [NSSet setWithArray:newItemIdList].count) {
        OWSFailDebug(@"New view item list has duplicates.");
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        return;
    }

    NSSet<NSString *> *oldItemIdSet = [NSSet setWithArray:oldItemIdList];
    NSSet<NSString *> *newItemIdSet = [NSSet setWithArray:newItemIdList];

    // We use sets and dictionaries here to ensure perf.
    // We use NSMutableOrderedSet to preserve item ordering.
    NSMutableOrderedSet<NSString *> *deletedItemIdSet = [NSMutableOrderedSet orderedSetWithArray:oldItemIdList];
    [deletedItemIdSet minusSet:newItemIdSet];
    NSMutableOrderedSet<NSString *> *insertedItemIdSet = [NSMutableOrderedSet orderedSetWithArray:newItemIdList];
    [insertedItemIdSet minusSet:oldItemIdSet];
    NSArray<NSString *> *deletedItemIdList = [deletedItemIdSet.array copy];
    NSArray<NSString *> *insertedItemIdList = [insertedItemIdSet.array copy];

    // Try to generate a series of "update items" that safely transform
    // the "old item list" into the "new item list".
    NSMutableArray<ConversationUpdateItem *> *updateItems = [NSMutableArray new];
    NSMutableArray<NSString *> *transformedItemList = [oldItemIdList mutableCopy];

    // 1. Deletes - Always perform deletes before inserts and updates.
    //
    // NOTE: We use reverseObjectEnumerator to ensure that items
    //       are deleted in reverse order, to avoid confusion around
    //       each deletion affecting the indices of subsequent deletions.
    for (NSString *itemId in deletedItemIdList.reverseObjectEnumerator) {
        OWSAssertDebug([oldItemIdSet containsObject:itemId]);
        OWSAssertDebug(![newItemIdSet containsObject:itemId]);

        NSUInteger oldIndex = [oldItemIdList indexOfObject:itemId];
        if (oldIndex == NSNotFound) {
            OWSFailDebug(@"Can't find index of deleted view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }

        [updateItems addObject:[[ConversationUpdateItem alloc] initWithUpdateItemType:ConversationUpdateItemType_Delete
                                                                             oldIndex:oldIndex
                                                                             newIndex:NSNotFound
                                                                             viewItem:nil]];
        [transformedItemList removeObject:itemId];
    }

    // 2. Inserts - Always perform inserts before updates.
    //
    // NOTE: We DO NOT use reverseObjectEnumerator.
    for (NSString *itemId in insertedItemIdList) {
        OWSAssertDebug(![oldItemIdSet containsObject:itemId]);
        OWSAssertDebug([newItemIdSet containsObject:itemId]);

        NSUInteger newIndex = [newItemIdList indexOfObject:itemId];
        if (newIndex == NSNotFound) {
            OWSFailDebug(@"Can't find index of inserted view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find inserted view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }

        [updateItems addObject:[[ConversationUpdateItem alloc] initWithUpdateItemType:ConversationUpdateItemType_Insert
                                                                             oldIndex:NSNotFound
                                                                             newIndex:newIndex
                                                                             viewItem:viewItem]];
        [transformedItemList insertObject:itemId atIndex:newIndex];
    }

    if (![newItemIdList isEqualToArray:transformedItemList]) {
        // We should be able to represent all transformations as a series of
        // inserts, updates and deletes - moves should not be necessary.
        //
        // TODO: The unread indicator might end up being an exception.
        OWSLogWarn(@"New and updated view item lists don't match.");
        return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
    }

    // In addition to "update" items from the database change notification,
    // we may need to update other items.  One example is neighbors of modified
    // cells. Another is cells whose appearance has changed due to the passage
    // of time.  We detect "dirty" items by whether or not they have cached layout
    // state, since that is cleared whenever we change the properties of the
    // item that affect its appearance.
    //
    // This replaces the setCellDrawingDependencyOffsets/
    // YapDatabaseViewChangedDependency logic offered by YDB mappings,
    // which only reflects changes in the data store, not at the view
    // level.
    NSMutableSet<NSString *> *updatedItemSet = [updatedItemSetParam mutableCopy];
    NSMutableSet<NSString *> *updatedNeighborItemSet = [NSMutableSet new];
    for (NSString *itemId in newItemIdSet) {
        if (![oldItemIdSet containsObject:itemId]) {
            continue;
        }
        if ([insertedItemIdSet containsObject:itemId] || [updatedItemSet containsObject:itemId]) {
            continue;
        }
        OWSAssertDebug(![deletedItemIdSet containsObject:itemId]);

        NSUInteger newIndex = [newItemIdList indexOfObject:itemId];
        if (newIndex == NSNotFound) {
            OWSFailDebug(@"Can't find index of holdover view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find holdover view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        if (!viewItem.hasCachedLayoutState) {
            [updatedItemSet addObject:itemId];
            [updatedNeighborItemSet addObject:itemId];
        }
    }

    // 3. Updates.
    //
    // NOTE: Order doesn't matter.
    for (NSString *itemId in updatedItemSet) {
        if (![newItemIdList containsObject:itemId]) {
            OWSFailDebug(@"Updated view item not in new view item list.");
            continue;
        }
        if ([insertedItemIdList containsObject:itemId]) {
            continue;
        }
        NSUInteger oldIndex = [oldItemIdList indexOfObject:itemId];
        if (oldIndex == NSNotFound) {
            OWSFailDebug(@"Can't find old index of updated view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        NSUInteger newIndex = [newItemIdList indexOfObject:itemId];
        if (newIndex == NSNotFound) {
            OWSFailDebug(@"Can't find new index of updated view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find inserted view item.");
            return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
        }
        [updateItems addObject:[[ConversationUpdateItem alloc] initWithUpdateItemType:ConversationUpdateItemType_Update
                                                                             oldIndex:oldIndex
                                                                             newIndex:newIndex
                                                                             viewItem:viewItem]];
    }

    BOOL shouldAnimateUpdates = [self shouldAnimateUpdateItems:updateItems
                                              oldViewItemCount:oldItemIdList.count
                                        updatedNeighborItemSet:updatedNeighborItemSet];

    return [self.delegate
        conversationViewModelDidUpdate:[ConversationUpdate diffUpdateWithUpdateItems:updateItems
                                                                shouldAnimateUpdates:shouldAnimateUpdates]];
}

- (BOOL)shouldAnimateUpdateItems:(NSArray<ConversationUpdateItem *> *)updateItems
                oldViewItemCount:(NSUInteger)oldViewItemCount
          updatedNeighborItemSet:(nullable NSMutableSet<NSString *> *)updatedNeighborItemSet
{
    OWSAssertDebug(updateItems);

    // If user sends a new outgoing message, don't animate the change.
    BOOL isOnlyModifyingLastMessage = YES;
    for (ConversationUpdateItem *updateItem in updateItems) {
        switch (updateItem.updateItemType) {
            case ConversationUpdateItemType_Delete:
                isOnlyModifyingLastMessage = NO;
                break;
            case ConversationUpdateItemType_Insert: {
                id<ConversationViewItem> viewItem = updateItem.viewItem;
                OWSAssertDebug(viewItem);
                switch (viewItem.interaction.interactionType) {
                    case OWSInteractionType_IncomingMessage:
                    case OWSInteractionType_OutgoingMessage:
                    case OWSInteractionType_TypingIndicator:
                        if (updateItem.newIndex < oldViewItemCount) {
                            isOnlyModifyingLastMessage = NO;
                        }
                        break;
                    default:
                        isOnlyModifyingLastMessage = NO;
                        break;
                }
                break;
            }
            case ConversationUpdateItemType_Update: {
                id<ConversationViewItem> viewItem = updateItem.viewItem;
                if ([updatedNeighborItemSet containsObject:viewItem.itemId]) {
                    continue;
                }
                OWSAssertDebug(viewItem);
                switch (viewItem.interaction.interactionType) {
                    case OWSInteractionType_IncomingMessage:
                    case OWSInteractionType_OutgoingMessage:
                    case OWSInteractionType_TypingIndicator:
                        // We skip animations for the last _two_
                        // interactions, not one since there
                        // may be a typing indicator.
                        if (updateItem.newIndex + 2 < updateItems.count) {
                            isOnlyModifyingLastMessage = NO;
                        }
                        break;
                    default:
                        isOnlyModifyingLastMessage = NO;
                        break;
                }
                break;
            }
        }
    }
    BOOL shouldAnimateRowUpdates = !isOnlyModifyingLastMessage;
    return shouldAnimateRowUpdates;
}

- (void)createNewMessageMapping
{
    if (self.thread.uniqueId.length < 1) {
        OWSFailDebug(@"uniqueId unexpectedly empty for thread: %@", self.thread);
    }

    self.messageMapping = [[ConversationMessageMapping alloc] initWithGroup:self.thread.uniqueId
                                                              desiredLength:self.initialMessageMappingLength];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMapping updateWithTransaction:transaction];
    }];
}

// This is more expensive than incremental updates.
//
// We call `resetMapping` for two separate reasons:
//
// * Most of the time, we call `resetMapping` after a severe error to get back into a known good state.
//   We then call `conversationViewModelDidReset` to get the view back into a known good state (by
//   scrolling to the bottom).
// * We also call `resetMapping` to load an additional page of older message.  We very much _do not_
// want to change view scroll state in this case.
- (void)resetMapping
{
    // Don't extend the mapping's desired length.
    [self resetMappingWithAdditionalLength:0];
}

- (void)resetMappingWithAdditionalLength:(NSUInteger)additionalLength
{
    OWSAssertDebug(self.messageMapping);

    [self updateMessageMappingWithAdditionalLength:additionalLength];

    self.collapseCutoffDate = [NSDate new];

    [self ensureDynamicInteractionsAndUpdateIfNecessary:NO];

    if (![self reloadViewItems]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self touchDbAsync];
}

#pragma mark - View Items

- (void)ensureConversationProfileState
{
    if (self.conversationProfileState) {
        return;
    }

    // Many OWSProfileManager methods aren't safe to call from inside a database
    // transaction, so do this work now.
    //
    // TODO: It'd be nice if these methods took a transaction.
    BOOL hasLocalProfile = [self.profileManager hasLocalProfile];
    BOOL isThreadInProfileWhitelist = [self.profileManager isThreadInProfileWhitelist:self.thread];
    BOOL hasUnwhitelistedMember = NO;
    for (NSString *recipientId in self.thread.recipientIdentifiers) {
        if (![self.profileManager isUserInProfileWhitelist:recipientId]) {
            hasUnwhitelistedMember = YES;
            break;
        }
    }

    ConversationProfileState *conversationProfileState = [ConversationProfileState new];
    conversationProfileState.hasLocalProfile = hasLocalProfile;
    conversationProfileState.isThreadInProfileWhitelist = isThreadInProfileWhitelist;
    conversationProfileState.hasUnwhitelistedMember = hasUnwhitelistedMember;
    self.conversationProfileState = conversationProfileState;
}

- (nullable TSInteraction *)firstCallOrMessageForLoadedInteractions:(NSArray<TSInteraction *> *)loadedInteractions

{
    for (TSInteraction *interaction in loadedInteractions) {
        switch (interaction.interactionType) {
            case OWSInteractionType_Unknown:
                OWSFailDebug(@"Unknown interaction type.");
                return nil;
            case OWSInteractionType_IncomingMessage:
            case OWSInteractionType_OutgoingMessage:
                return interaction;
            case OWSInteractionType_Error:
            case OWSInteractionType_Info:
                break;
            case OWSInteractionType_Call:
            case OWSInteractionType_Offer:
            case OWSInteractionType_TypingIndicator:
                break;
        }
    }
    return nil;
}

- (nullable OWSContactOffersInteraction *)
    tryToBuildContactOffersInteractionWithTransaction:(YapDatabaseReadTransaction *)transaction
                                   loadedInteractions:(NSArray<TSInteraction *> *)loadedInteractions
                                     canLoadMoreItems:(BOOL)canLoadMoreItems
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(self.conversationProfileState);

    if (canLoadMoreItems) {
        // Only show contact offers at the start of the conversation.
        return nil;
    }

    BOOL hasLocalProfile = self.conversationProfileState.hasLocalProfile;
    BOOL isThreadInProfileWhitelist = self.conversationProfileState.isThreadInProfileWhitelist;
    BOOL hasUnwhitelistedMember = self.conversationProfileState.hasUnwhitelistedMember;

    TSThread *thread = self.thread;
    BOOL isContactThread = [thread isKindOfClass:[TSContactThread class]];
    if (!isContactThread) {
        return nil;
    }
    TSContactThread *contactThread = (TSContactThread *)thread;
    if (contactThread.hasDismissedOffers) {
        return nil;
    }

    NSString *localNumber = [self.tsAccountManager localNumber];
    OWSAssertDebug(localNumber.length > 0);

    TSInteraction *firstCallOrMessage = [self firstCallOrMessageForLoadedInteractions:loadedInteractions];
    if (!firstCallOrMessage) {
        return nil;
    }

    BOOL hasTooManyOutgoingMessagesToBlock;
    if (self.hasTooManyOutgoingMessagesToBlockCached) {
        hasTooManyOutgoingMessagesToBlock = YES;
    } else {
        NSUInteger outgoingMessageCount =
            [[TSDatabaseView threadOutgoingMessageDatabaseView:transaction] numberOfItemsInGroup:thread.uniqueId];

        const int kMaxBlockOfferOutgoingMessageCount = 10;
        hasTooManyOutgoingMessagesToBlock = (outgoingMessageCount > kMaxBlockOfferOutgoingMessageCount);
        self.hasTooManyOutgoingMessagesToBlockCached = hasTooManyOutgoingMessagesToBlock;
    }

    BOOL shouldHaveBlockOffer = YES;
    BOOL shouldHaveAddToContactsOffer = YES;
    BOOL shouldHaveAddToProfileWhitelistOffer = YES;

    NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

    if ([recipientId isEqualToString:localNumber]) {
        // Don't add self to contacts.
        shouldHaveAddToContactsOffer = NO;
        // Don't bother to block self.
        shouldHaveBlockOffer = NO;
        // Don't bother adding self to profile whitelist.
        shouldHaveAddToProfileWhitelistOffer = NO;
    } else {
        if ([[self.blockingManager blockedPhoneNumbers] containsObject:recipientId]) {
            // Only create "add to contacts" offers for users which are not already blocked.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers for users which are not already blocked.
            shouldHaveBlockOffer = NO;
            // Don't create profile whitelist offers for users which are not already blocked.
            shouldHaveAddToProfileWhitelistOffer = NO;
        }

        if ([self.contactsManager hasSignalAccountForRecipientId:recipientId]) {
            // Only create "add to contacts" offers for non-contacts.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers for non-contacts.
            shouldHaveBlockOffer = NO;
            // Don't create profile whitelist offers for non-contacts.
            shouldHaveAddToProfileWhitelistOffer = NO;
        }
    }

    if (hasTooManyOutgoingMessagesToBlock) {
        // If the user has sent more than N messages, don't show a block offer.
        shouldHaveBlockOffer = NO;
    }

    BOOL hasOutgoingBeforeIncomingInteraction = [firstCallOrMessage isKindOfClass:[TSOutgoingMessage class]];
    if ([firstCallOrMessage isKindOfClass:[TSCall class]]) {
        TSCall *call = (TSCall *)firstCallOrMessage;
        hasOutgoingBeforeIncomingInteraction
            = (call.callType == RPRecentCallTypeOutgoing || call.callType == RPRecentCallTypeOutgoingIncomplete);
    }
    if (hasOutgoingBeforeIncomingInteraction) {
        // If there is an outgoing message before an incoming message
        // the local user initiated this conversation, don't show a block offer.
        shouldHaveBlockOffer = NO;
    }

    if (!hasLocalProfile || isThreadInProfileWhitelist) {
        // Don't show offer if thread is local user hasn't configured their profile.
        // Don't show offer if thread is already in profile whitelist.
        shouldHaveAddToProfileWhitelistOffer = NO;
    } else if (thread.isGroupThread && !hasUnwhitelistedMember) {
        // Don't show offer in group thread if all members are already individually
        // whitelisted.
        shouldHaveAddToProfileWhitelistOffer = NO;
    }

    BOOL shouldHaveContactOffers
        = (shouldHaveBlockOffer || shouldHaveAddToContactsOffer || shouldHaveAddToProfileWhitelistOffer);
    if (!shouldHaveContactOffers) {
        return nil;
    }

    // We want the offers to be the first interactions in their
    // conversation's timeline, so we back-date them to slightly before
    // the first message - or at an arbitrary old timestamp if the
    // conversation has no messages.
    uint64_t contactOffersTimestamp = firstCallOrMessage.timestamp - 1;
    // This view model uses the "unique id" to identify this interaction,
    // but the interaction is never saved in the database so the specific
    // value doesn't matter.
    NSString *uniqueId = @"contact-offers";
    OWSContactOffersInteraction *offersMessage =
        [[OWSContactOffersInteraction alloc] initInteractionWithUniqueId:uniqueId
                                                               timestamp:contactOffersTimestamp
                                                                  thread:thread
                                                           hasBlockOffer:shouldHaveBlockOffer
                                                   hasAddToContactsOffer:shouldHaveAddToContactsOffer
                                           hasAddToProfileWhitelistOffer:shouldHaveAddToProfileWhitelistOffer
                                                             recipientId:recipientId
                                                     beforeInteractionId:firstCallOrMessage.uniqueId];

    OWSLogInfo(@"Creating contact offers: %@ (%llu)", offersMessage.uniqueId, offersMessage.sortId);
    return offersMessage;
}

// This is a key method.  It builds or rebuilds the list of
// cell view models.
//
// Returns NO on error.
- (BOOL)reloadViewItems
{
    NSMutableArray<id<ConversationViewItem>> *viewItems = [NSMutableArray new];
    NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache = [NSMutableDictionary new];

    NSArray<NSString *> *loadedUniqueIds = [self.messageMapping loadedUniqueIds];
    BOOL isGroupThread = self.thread.isGroupThread;
    ConversationStyle *conversationStyle = self.delegate.conversationStyle;

    [self ensureConversationProfileState];

    __block BOOL hasError = NO;
    id<ConversationViewItem> (^tryToAddViewItem)(TSInteraction *, YapDatabaseReadTransaction *)
        = ^(TSInteraction *interaction, YapDatabaseReadTransaction *transaction) {
              OWSAssertDebug(interaction.uniqueId.length > 0);

              id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[interaction.uniqueId];
              if (!viewItem) {
                  viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:interaction
                                                                            isGroupThread:isGroupThread
                                                                              transaction:transaction
                                                                        conversationStyle:conversationStyle];
              }
              OWSAssertDebug(!viewItemCache[interaction.uniqueId]);
              viewItemCache[interaction.uniqueId] = viewItem;
              [viewItems addObject:viewItem];

              return viewItem;
          };

    NSMutableSet<NSString *> *interactionIds = [NSMutableSet new];
    BOOL canLoadMoreItems = self.messageMapping.canLoadMore;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];

        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssertDebug(viewTransaction);
        for (NSString *uniqueId in loadedUniqueIds) {
            TSInteraction *_Nullable interaction =
                [TSInteraction fetchObjectWithUniqueID:uniqueId transaction:transaction];
            if (!interaction) {
                OWSFailDebug(@"missing interaction in message mapping: %@.", uniqueId);
                // TODO: Add analytics.
                hasError = YES;
                continue;
            }
            if (!interaction.uniqueId) {
                OWSFailDebug(@"invalid interaction in message mapping: %@.", interaction);
                // TODO: Add analytics.
                hasError = YES;
                continue;
            }
            [interactions addObject:interaction];
            if ([interactionIds containsObject:interaction.uniqueId]) {
                OWSFailDebug(@"Duplicate interaction: %@", interaction.uniqueId);
                continue;
            }
            [interactionIds addObject:interaction.uniqueId];
        }

        OWSContactOffersInteraction *_Nullable offers =
            [self tryToBuildContactOffersInteractionWithTransaction:transaction
                                                 loadedInteractions:interactions
                                                   canLoadMoreItems:canLoadMoreItems];
        if (offers && [interactionIds containsObject:offers.beforeInteractionId]) {
            id<ConversationViewItem> offersItem = tryToAddViewItem(offers, transaction);
            if ([offersItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]) {
                OWSContactOffersInteraction *oldOffers = (OWSContactOffersInteraction *)offersItem.interaction;
                BOOL didChange = (oldOffers.hasBlockOffer != offers.hasBlockOffer
                    || oldOffers.hasAddToContactsOffer != offers.hasAddToContactsOffer
                    || oldOffers.hasAddToProfileWhitelistOffer != offers.hasAddToProfileWhitelistOffer);
                if (didChange) {
                    [offersItem clearCachedLayoutState];
                }
            } else {
                OWSFailDebug(@"Unexpected offers item: %@", offersItem.interaction.class);
            }
        }

        for (TSInteraction *interaction in interactions) {
            tryToAddViewItem(interaction, transaction);
        }
    }];

    // This will usually be redundant, but this will resolve one of the symptoms
    // of the "corrupt YDB view" issue caused by multi-process writes.
    [viewItems sortUsingComparator:^NSComparisonResult(id<ConversationViewItem> left, id<ConversationViewItem> right) {
        return [left.interaction compareForSorting:right.interaction];
    }];

    if (self.unsavedOutgoingMessages.count > 0) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            for (TSOutgoingMessage *outgoingMessage in self.unsavedOutgoingMessages) {
                if ([interactionIds containsObject:outgoingMessage.uniqueId]) {
                    OWSFailDebug(@"Duplicate interaction: %@", outgoingMessage.uniqueId);
                    continue;
                }
                tryToAddViewItem(outgoingMessage, transaction);
                [interactionIds addObject:outgoingMessage.uniqueId];
            }
        }];
    }

    if (self.typingIndicatorsSender) {
        OWSTypingIndicatorInteraction *typingIndicatorInteraction =
            [[OWSTypingIndicatorInteraction alloc] initWithThread:self.thread
                                                        timestamp:[NSDate ows_millisecondTimeStamp]
                                                      recipientId:self.typingIndicatorsSender];

        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            tryToAddViewItem(typingIndicatorInteraction, transaction);
        }];
    }

    // Flag to ensure that we only increment once per launch.
    if (hasError) {
        OWSLogWarn(@"incrementing version of: %@", TSMessageDatabaseViewExtensionName);
        [OWSPrimaryStorage incrementVersionOfDatabaseExtension:TSMessageDatabaseViewExtensionName];
    }

    // Update the "break" properties (shouldShowDate and unreadIndicator) of the view items.
    BOOL shouldShowDateOnNextViewItem = YES;
    uint64_t previousViewItemTimestamp = 0;
    OWSUnreadIndicator *_Nullable unreadIndicator = self.dynamicInteractions.unreadIndicator;
    uint64_t collapseCutoffTimestamp = [NSDate ows_millisecondsSince1970ForDate:self.collapseCutoffDate];

    BOOL hasPlacedUnreadIndicator = NO;
    for (id<ConversationViewItem> viewItem in viewItems) {
        BOOL canShowDate = NO;
        switch (viewItem.interaction.interactionType) {
            case OWSInteractionType_Unknown:
            case OWSInteractionType_Offer:
            case OWSInteractionType_TypingIndicator:
                canShowDate = NO;
                break;
            case OWSInteractionType_IncomingMessage:
            case OWSInteractionType_OutgoingMessage:
            case OWSInteractionType_Error:
            case OWSInteractionType_Info:
            case OWSInteractionType_Call:
                canShowDate = YES;
                break;
        }

        uint64_t viewItemTimestamp = viewItem.interaction.timestamp;
        OWSAssertDebug(viewItemTimestamp > 0);

        BOOL shouldShowDate = NO;
        if (previousViewItemTimestamp == 0) {
            shouldShowDateOnNextViewItem = YES;
        } else if (![DateUtil isSameDayWithTimestamp:previousViewItemTimestamp timestamp:viewItemTimestamp]) {
            shouldShowDateOnNextViewItem = YES;
        }

        if (shouldShowDateOnNextViewItem && canShowDate) {
            shouldShowDate = YES;
            shouldShowDateOnNextViewItem = NO;
        }

        viewItem.shouldShowDate = shouldShowDate;

        previousViewItemTimestamp = viewItemTimestamp;

        // When a conversation without unread messages receives an incoming message,
        // we call ensureDynamicInteractions to ensure that the unread indicator (etc.)
        // state is updated accordingly.  However this is done in a separate transaction.
        // We don't want to show the incoming message _without_ an unread indicator and
        // then immediately re-render it _with_ an unread indicator.
        //
        // To avoid this, we use a temporary instance of OWSUnreadIndicator whenever
        // we find an unread message that _should_ have an unread indicator, but no
        // unread indicator exists yet on dynamicInteractions.
        BOOL isItemUnread = ([viewItem.interaction conformsToProtocol:@protocol(OWSReadTracking)]
            && !((id<OWSReadTracking>)viewItem.interaction).wasRead);
        if (isItemUnread && !unreadIndicator && !hasPlacedUnreadIndicator && !self.hasClearedUnreadMessagesIndicator) {
            unreadIndicator = [[OWSUnreadIndicator alloc] initWithFirstUnseenSortId:viewItem.interaction.sortId
                                                              hasMoreUnseenMessages:NO
                                               missingUnseenSafetyNumberChangeCount:0
                                                            unreadIndicatorPosition:0];
        }

        // Place the unread indicator onto the first appropriate view item,
        // if any.
        if (unreadIndicator && viewItem.interaction.sortId >= unreadIndicator.firstUnseenSortId) {
            viewItem.unreadIndicator = unreadIndicator;
            unreadIndicator = nil;
            hasPlacedUnreadIndicator = YES;
        } else {
            viewItem.unreadIndicator = nil;
        }
    }
    if (unreadIndicator) {
        // This isn't necessarily a bug - all of the interactions after the
        // unread indicator may have disappeared or been deleted.
        OWSLogWarn(@"Couldn't find an interaction to hang the unread indicator on.");
    }

    // Update the properties of the view items.
    //
    // NOTE: This logic uses the break properties which are set in the previous pass.
    for (NSUInteger i = 0; i < viewItems.count; i++) {
        id<ConversationViewItem> viewItem = viewItems[i];
        id<ConversationViewItem> _Nullable previousViewItem = (i > 0 ? viewItems[i - 1] : nil);
        id<ConversationViewItem> _Nullable nextViewItem = (i + 1 < viewItems.count ? viewItems[i + 1] : nil);
        BOOL shouldShowSenderAvatar = NO;
        BOOL shouldHideFooter = NO;
        BOOL isFirstInCluster = YES;
        BOOL isLastInCluster = YES;
        NSAttributedString *_Nullable senderName = nil;

        OWSInteractionType interactionType = viewItem.interaction.interactionType;
        NSString *timestampText = [DateUtil formatTimestampShort:viewItem.interaction.timestamp];

        if (interactionType == OWSInteractionType_OutgoingMessage) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
            MessageReceiptStatus receiptStatus =
                [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
            BOOL isDisappearingMessage = outgoingMessage.isExpiringMessage;

            if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                TSOutgoingMessage *nextOutgoingMessage = (TSOutgoingMessage *)nextViewItem.interaction;
                MessageReceiptStatus nextReceiptStatus =
                    [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:nextOutgoingMessage];
                NSString *nextTimestampText = [DateUtil formatTimestampShort:nextViewItem.interaction.timestamp];

                // We can skip the "outgoing message status" footer if the next message
                // has the same footer and no "date break" separates us...
                // ...but always show "failed to send" status
                // ...and always show the "disappearing messages" animation.
                shouldHideFooter
                    = ([timestampText isEqualToString:nextTimestampText] && receiptStatus == nextReceiptStatus
                        && outgoingMessage.messageState != TSOutgoingMessageStateFailed
                        && outgoingMessage.messageState != TSOutgoingMessageStateSending && !nextViewItem.hasCellHeader
                        && !isDisappearingMessage);
            }

            // clustering
            if (previousViewItem == nil) {
                isFirstInCluster = YES;
            } else if (viewItem.hasCellHeader) {
                isFirstInCluster = YES;
            } else {
                isFirstInCluster = previousViewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage;
            }

            if (nextViewItem == nil) {
                isLastInCluster = YES;
            } else if (nextViewItem.hasCellHeader) {
                isLastInCluster = YES;
            } else {
                isLastInCluster = nextViewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage;
            }
        } else if (interactionType == OWSInteractionType_IncomingMessage) {

            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)viewItem.interaction;
            NSString *incomingSenderId = incomingMessage.authorId;
            OWSAssertDebug(incomingSenderId.length > 0);
            BOOL isDisappearingMessage = incomingMessage.isExpiringMessage;

            NSString *_Nullable nextIncomingSenderId = nil;
            if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                TSIncomingMessage *nextIncomingMessage = (TSIncomingMessage *)nextViewItem.interaction;
                nextIncomingSenderId = nextIncomingMessage.authorId;
                OWSAssertDebug(nextIncomingSenderId.length > 0);
            }

            if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                NSString *nextTimestampText = [DateUtil formatTimestampShort:nextViewItem.interaction.timestamp];
                // We can skip the "incoming message status" footer in a cluster if the next message
                // has the same footer and no "date break" separates us.
                // ...but always show the "disappearing messages" animation.
                shouldHideFooter = ([timestampText isEqualToString:nextTimestampText] && !nextViewItem.hasCellHeader &&
                    [NSObject isNullableObject:nextIncomingSenderId equalTo:incomingSenderId]
                    && !isDisappearingMessage);
            }

            // clustering
            if (previousViewItem == nil) {
                isFirstInCluster = YES;
            } else if (viewItem.hasCellHeader) {
                isFirstInCluster = YES;
            } else if (previousViewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
                isFirstInCluster = YES;
            } else {
                TSIncomingMessage *previousIncomingMessage = (TSIncomingMessage *)previousViewItem.interaction;
                isFirstInCluster = ![incomingSenderId isEqual:previousIncomingMessage.authorId];
            }

            if (nextViewItem == nil) {
                isLastInCluster = YES;
            } else if (nextViewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
                isLastInCluster = YES;
            } else if (nextViewItem.hasCellHeader) {
                isLastInCluster = YES;
            } else {
                TSIncomingMessage *nextIncomingMessage = (TSIncomingMessage *)nextViewItem.interaction;
                isLastInCluster = ![incomingSenderId isEqual:nextIncomingMessage.authorId];
            }

            if (viewItem.isGroupThread) {
                // Show the sender name for incoming group messages unless
                // the previous message has the same sender name and
                // no "date break" separates us.
                BOOL shouldShowSenderName = YES;
                if (previousViewItem && previousViewItem.interaction.interactionType == interactionType) {

                    TSIncomingMessage *previousIncomingMessage = (TSIncomingMessage *)previousViewItem.interaction;
                    NSString *previousIncomingSenderId = previousIncomingMessage.authorId;
                    OWSAssertDebug(previousIncomingSenderId.length > 0);

                    shouldShowSenderName
                        = (![NSObject isNullableObject:previousIncomingSenderId equalTo:incomingSenderId]
                            || viewItem.hasCellHeader);
                }
                if (shouldShowSenderName) {
                    senderName = [self.contactsManager
                        attributedContactOrProfileNameForPhoneIdentifier:incomingSenderId
                                                       primaryAttributes:[OWSMessageBubbleView
                                                                             senderNamePrimaryAttributes]
                                                     secondaryAttributes:[OWSMessageBubbleView
                                                                             senderNameSecondaryAttributes]];
                }

                // Show the sender avatar for incoming group messages unless
                // the next message has the same sender avatar and
                // no "date break" separates us.
                shouldShowSenderAvatar = YES;
                if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                    shouldShowSenderAvatar = (![NSObject isNullableObject:nextIncomingSenderId equalTo:incomingSenderId]
                        || nextViewItem.hasCellHeader);
                }
            }
        }

        if (viewItem.interaction.receivedAtTimestamp > collapseCutoffTimestamp) {
            shouldHideFooter = NO;
        }

        viewItem.isFirstInCluster = isFirstInCluster;
        viewItem.isLastInCluster = isLastInCluster;
        viewItem.shouldShowSenderAvatar = shouldShowSenderAvatar;
        viewItem.shouldHideFooter = shouldHideFooter;
        viewItem.senderName = senderName;
    }

    self.viewItems = viewItems;
    self.viewItemCache = viewItemCache;

    return !hasError;
}

- (void)appendUnsavedOutgoingTextMessage:(TSOutgoingMessage *)outgoingMessage
{
    // Because the message isn't yet saved, we don't have sufficient information to build
    // in-memory placeholder for message types more complex than plain text.
    OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
    OWSAssertDebug(outgoingMessage.contactShare == nil);

    NSMutableArray<TSOutgoingMessage *> *unsavedOutgoingMessages = [self.unsavedOutgoingMessages mutableCopy];
    [unsavedOutgoingMessages addObject:outgoingMessage];
    self.unsavedOutgoingMessages = unsavedOutgoingMessages;

    [self updateForTransientItems];
}

// Whenever an interaction is modified, we need to reload it from the DB
// and update the corresponding view item.
- (void)reloadInteractionForViewItem:(id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    // This should never happen, but don't crash in production if we have a bug.
    if (!viewItem) {
        return;
    }

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        TSInteraction *_Nullable interaction =
            [TSInteraction fetchObjectWithUniqueID:viewItem.interaction.uniqueId transaction:transaction];
        if (!interaction) {
            OWSFailDebug(@"could not reload interaction");
        } else {
            [viewItem replaceInteraction:interaction transaction:transaction];
        }
    }];
}

- (nullable NSIndexPath *)ensureLoadWindowContainsQuotedReply:(OWSQuotedReplyModel *)quotedReply
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(quotedReply);
    OWSAssertDebug(quotedReply.timestamp > 0);
    OWSAssertDebug(quotedReply.authorId.length > 0);

    if (quotedReply.isRemotelySourced) {
        return nil;
    }

    __block NSIndexPath *_Nullable indexPath = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        TSInteraction *_Nullable quotedInteraction =
            [ThreadUtil findInteractionInThreadByTimestamp:quotedReply.timestamp
                                                  authorId:quotedReply.authorId
                                            threadUniqueId:self.thread.uniqueId
                                               transaction:transaction];
        if (!quotedInteraction) {
            return;
        }

        indexPath =
            [self.messageMapping ensureLoadWindowContainsUniqueId:quotedInteraction.uniqueId transaction:transaction];
    }];

    self.collapseCutoffDate = [NSDate new];

    [self ensureDynamicInteractionsAndUpdateIfNecessary:NO];

    if (![self reloadViewItems]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
    [self.delegate conversationViewModelRangeDidChange];

    return indexPath;
}

- (nullable NSIndexPath *)ensureLoadWindowContainsInteractionId:(NSString *)interactionId
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(interactionId);

    __block NSIndexPath *_Nullable indexPath = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        indexPath = [self.messageMapping ensureLoadWindowContainsUniqueId:interactionId transaction:transaction];
    }];

    self.collapseCutoffDate = [NSDate new];

    [self ensureDynamicInteractionsAndUpdateIfNecessary:NO];

    if (![self reloadViewItems]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
    [self.delegate conversationViewModelRangeDidChange];

    return indexPath;
}

- (nullable NSNumber *)findGroupIndexOfThreadInteraction:(TSInteraction *)interaction
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(interaction);
    OWSAssertDebug(transaction);

    YapDatabaseAutoViewTransaction *_Nullable extension = [transaction extension:TSMessageDatabaseViewExtensionName];
    if (!extension) {
        OWSFailDebug(@"Couldn't load view.");
        return nil;
    }

    NSUInteger groupIndex = 0;
    BOOL foundInGroup =
        [extension getGroup:nil index:&groupIndex forKey:interaction.uniqueId inCollection:TSInteraction.collection];
    if (!foundInGroup) {
        OWSLogError(@"Couldn't find quoted message in group.");
        return nil;
    }
    return @(groupIndex);
}

- (void)typingIndicatorStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.thread);

    if (notification.object && ![notification.object isEqual:self.thread.uniqueId]) {
        return;
    }

    self.typingIndicatorsSender = [self.typingIndicators typingRecipientIdForThread:self.thread];
}

- (void)setTypingIndicatorsSender:(nullable NSString *)typingIndicatorsSender
{
    OWSAssertIsOnMainThread();

    BOOL didChange = ![NSObject isNullableObject:typingIndicatorsSender equalTo:_typingIndicatorsSender];

    _typingIndicatorsSender = typingIndicatorsSender;

    // Update the view items if necessary.
    // We don't have to do this if they haven't been configured yet.
    if (didChange && self.viewItems != nil) {
        // When we receive an incoming message, we clear any typing indicators
        // from that sender.  Ideally, we'd like both changes (disappearance of
        // the typing indicators, appearance of the incoming message) to show up
        // in the view at the same time, rather than as a "jerky" two-step
        // visual change.
        //
        // Unfortunately, the view model learns of these changes by separate
        // channels: the incoming message is a database modification and the
        // typing indicator change arrives via this notification.
        //
        // Therefore we pause briefly before updating the view model to reflect
        // typing indicators state changes so that the database modification
        // can usually arrive first and update the view to reflect both changes.
        __weak ConversationViewModel *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf updateForTransientItems];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
