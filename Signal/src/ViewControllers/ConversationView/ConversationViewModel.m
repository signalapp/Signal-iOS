//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewModel.h"
#import "ConversationViewItem.h"
#import "DateUtil.h"
#import "OWSMessageBubbleView.h"
#import "OWSQuotedReplyModel.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationProfileState : NSObject

@property (nonatomic) BOOL hasLocalProfile;
@property (nonatomic) BOOL isThreadInProfileWhitelist;
@property (nonatomic) BOOL hasUnwhitelistedMember;

@end

#pragma mark -

@implementation ConversationProfileState

@end

@implementation ConversationViewState

- (instancetype)initWithViewItems:(NSArray<id<ConversationViewItem>> *)viewItems
                   focusMessageId:(nullable NSString *)focusMessageId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _viewItems = viewItems;
    NSMutableDictionary<NSString *, NSNumber *> *interactionIndexMap = [NSMutableDictionary new];
    NSMutableArray<NSString *> *interactionIds = [NSMutableArray new];
    for (NSUInteger i = 0; i < self.viewItems.count; i++) {
        id<ConversationViewItem> viewItem = self.viewItems[i];
        interactionIndexMap[viewItem.interaction.uniqueId] = @(i);
        [interactionIds addObject:viewItem.interaction.uniqueId];
        if (focusMessageId != nil && [focusMessageId isEqualToString:viewItem.interaction.uniqueId]) {
            _focusItemIndex = @(i);
        }
        if ([viewItem.interaction isKindOfClass:OWSUnreadIndicatorInteraction.class]) {
            _unreadIndicatorIndex = @(i);
        }
    }
    _interactionIndexMap = [interactionIndexMap copy];
    _interactionIds = [interactionIds copy];

    return self;
}

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

@interface ConversationUpdate ()

@property (nonatomic) BOOL shouldAnimateUpdates;
@property (nonatomic) BOOL shouldJumpToOutgoingMessage;

@end

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
    _shouldJumpToOutgoingMessage = YES;

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

@interface ConversationViewModel () <UIDatabaseSnapshotDelegate>

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

@property (nonatomic) ConversationViewState *viewState;
@property (nonatomic) NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache;

@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic) NSDate *collapseCutoffDate;
@property (nonatomic, nullable) SignalServiceAddress *typingIndicatorsSender;

@property (nonatomic, nullable) ConversationProfileState *conversationProfileState;
@property (nonatomic) BOOL hasTooManyOutgoingMessagesToBlockCached;

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
    _unsavedOutgoingMessages = @[];
    _focusMessageIdOnOpen = focusMessageIdOnOpen;
    _viewState = [[ConversationViewState alloc] initWithViewItems:@[] focusMessageId:focusMessageIdOnOpen];
    _messageMapping = [[ConversationMessageMapping alloc] initWithThread:thread];
    _collapseCutoffDate = [NSDate new];

    [self configure];

    return self;
}

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
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
                                             selector:@selector(typingIndicatorStateDidChange:)
                                                 name:[OWSTypingIndicatorsImpl typingIndicatorStateDidChange]
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationNameProfileWhitelistDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationName_BlockListDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localProfileDidChange:)
                                                 name:kNSNotificationNameLocalProfileDidChange
                                               object:nil];
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
    self.typingIndicatorsSender = [self.typingIndicators typingAddressForThread:self.thread];

    [BenchManager benchWithTitle:@"loading initial interactions"
                           block:^{
                               [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                                   NSError *error;
                                   [self.messageMapping
                                       loadInitialMessagePageWithFocusMessageId:self.focusMessageIdOnOpen
                                                                    transaction:transaction
                                                                          error:&error];
                                   if (error != nil) {
                                       OWSFailDebug(@"error: %@", error);
                                   }
                                   if (![self reloadViewItemsWithTransaction:transaction]) {
                                       OWSFailDebug(@"failed to reload view items in configureForThread.");
                                   }
                               }];
                           }];

    OWSAssert(StorageCoordinator.dataStoreForUI == DataStoreGrdb);
    [self.databaseStorage appendUIDatabaseSnapshotDelegate:self];
}

- (void)viewDidLoad
{
    [self addNotificationListeners];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self resetClearedUnreadMessagesIndicator];
}

- (void)viewDidResetContentAndLayoutWithTransaction:(SDSAnyReadTransaction *)transaction
{
    self.collapseCutoffDate = [NSDate new];
    if (![self reloadViewItemsWithTransaction:transaction]) {
        OWSFailDebug(@"failed to reload view items in resetContentAndLayout.");
    }
}

- (BOOL)canLoadOlderItems
{
    return self.messageMapping.canLoadOlder;
}

- (BOOL)canLoadNewerItems
{
    return self.messageMapping.canLoadNewer;
}

- (void)appendOlderItemsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSError *error;
    ConversationMessageMappingDiff *diff = [self.messageMapping loadOlderMessagePageWithTransaction:transaction
                                                                                              error:&error];

    if (error != nil) {
        OWSFailDebug(@"Could not determine diff. error: %@", error);
        return;
    }

    [self updateViewForAppendWithDiff:diff transaction:transaction];
}

- (void)appendNewerItemsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSError *error;
    ConversationMessageMappingDiff *diff = [self.messageMapping loadNewerMessagePageWithTransaction:transaction
                                                                                              error:&error];

    if (error != nil) {
        OWSFailDebug(@"Could not determine diff. error: %@", error);
        return;
    }

    [self updateViewForAppendWithDiff:diff transaction:transaction];
}

- (void)updateViewForAppendWithDiff:(ConversationMessageMappingDiff *)diff
                        transaction:(SDSAnyReadTransaction *)transaction
{
    [self.delegate conversationViewModelWillLoadMoreItems];

    if (diff.updatedItemIds.count > 0) {
        OWSFailDebug(@"Unexpectedly had updated items while appending older/newer items.");
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate transaction:transaction];
        [self.delegate conversationViewModelDidLoadMoreItems];
        [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];
        return;
    }

    if (diff.addedItemIds.count < 1 && diff.removedItemIds.count < 1 && diff.updatedItemIds.count < 1) {
        // This probably isn't an error; presumably the modifications
        // occurred outside the load window.
        OWSLogDebug(@"Empty diff.");
        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate transaction:transaction];
        [self.delegate conversationViewModelDidLoadMoreItems];
        [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];
        return;
    }

    NSArray<NSString *> *oldItemIdList = self.viewState.interactionIds;

    if (![self reloadViewItemsWithTransaction:transaction]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mapping.");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMappingWithTransaction:transaction];
        [self.delegate conversationViewModelDidLoadMoreItems];
        [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];
        return;
    }

    ConversationUpdate *conversationUpdate = [self conversationUpdateWithOldItemIdList:oldItemIdList
                                                                        updatedItemSet:[NSSet set]];

    // We never want to animate appends.
    conversationUpdate.shouldAnimateUpdates = NO;

    // We never want to jump to newly visible outgoing messages during appends.
    conversationUpdate.shouldJumpToOutgoingMessage = NO;

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewState.viewItems.count);

    [self.delegate conversationViewModelDidUpdate:conversationUpdate transaction:transaction];
    [self.delegate conversationViewModelDidLoadMoreItems];
    [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];
}

- (void)clearUnreadMessagesIndicator
{
    OWSAssertIsOnMainThread();
    self.messageMapping.oldestUnreadInteraction = nil;

    // Once we've cleared the unread messages indicator,
    // make sure we don't show it again.
    self.hasClearedUnreadMessagesIndicator = YES;
}

- (void)resetClearedUnreadMessagesIndicator
{
    OWSAssertIsOnMainThread();
    self.messageMapping.oldestUnreadInteraction = nil;
    self.hasClearedUnreadMessagesIndicator = NO;
    [self updateForTransientItems];
}

#pragma mark - GRDB Updates

- (void)uiDatabaseSnapshotWillUpdate
{
    [self.delegate conversationViewModelWillUpdate];
}

- (void)uiDatabaseSnapshotDidUpdateWithDatabaseChanges:(id<UIDatabaseChanges>)databaseChanges
{
    if (![databaseChanges.threadUniqueIds containsObject:self.thread.uniqueId]) {
        // Ignoring irrelevant update.
        return;
    }

    [self anyDBDidUpdateWithUpdatedInteractionIds:databaseChanges.interactionUniqueIds];
}

- (void)uiDatabaseSnapshotDidUpdateExternally
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");
}

- (void)uiDatabaseSnapshotDidReset
{
    [self resetMappingWithSneakyTransaction];
}

#pragma mark -

- (void)anyDBDidUpdateWithUpdatedInteractionIds:(NSSet<NSString *> *)updatedInteractionIds
{
    __block ConversationMessageMappingDiff *_Nullable diff = nil;
    __block NSError *error;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        diff = [self.messageMapping updateAndCalculateDiffWithUpdatedInteractionIds:updatedInteractionIds
                                                                        transaction:transaction
                                                                              error:&error];
    }];
    if (error != nil || diff == nil) {
        OWSFailDebug(@"Could not determine diff. error: %@", error);
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMappingWithSneakyTransaction];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    NSMutableSet<NSString *> *diffAddedItemIds = [diff.addedItemIds mutableCopy];
    NSMutableSet<NSString *> *diffRemovedItemIds = [diff.removedItemIds mutableCopy];
    NSMutableSet<NSString *> *diffUpdatedItemIds = [diff.updatedItemIds mutableCopy];

    // If we have a thread details item, insert it into the updated items. We assume
    // it always needs to update, because it's rarely actually loaded and can be changed
    // by a large number of thread updates.
    if (self.shouldShowThreadDetails) {
        [diffUpdatedItemIds addObject:OWSThreadDetailsInteraction.ThreadDetailsId];
    }

    for (TSOutgoingMessage *unsavedOutgoingMessage in self.unsavedOutgoingMessages) {
        BOOL isFound = ([diff.addedItemIds containsObject:unsavedOutgoingMessage.uniqueId] ||
            [diff.removedItemIds containsObject:unsavedOutgoingMessage.uniqueId] ||
            [diff.updatedItemIds containsObject:unsavedOutgoingMessage.uniqueId] ||
            [updatedInteractionIds containsObject:unsavedOutgoingMessage.uniqueId]);
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

    if (diffAddedItemIds.count < 1 && diffRemovedItemIds.count < 1 && diffUpdatedItemIds.count < 1) {
        // This probably isn't an error; presumably the modifications
        // occurred outside the load window.
        OWSLogDebug(@"Empty diff.");
        [self.delegate conversationViewModelDidUpdateWithSneakyTransaction:ConversationUpdate.minorUpdate];
        return;
    }

    NSArray<NSString *> *oldItemIdList = self.viewState.interactionIds;

    // We need to reload any modified interactions _before_ we call
    // reloadViewItems.
    __block BOOL hasMalformedRowChange = NO;
    NSMutableSet<NSString *> *updatedItemSet = [NSMutableSet new];

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        for (NSString *uniqueId in diffUpdatedItemIds) {
            id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[uniqueId];
            if (viewItem) {
                [self reloadInteractionForViewItem:viewItem transaction:transaction];
                [updatedItemSet addObject:viewItem.itemId];
            } else {
                OWSFailDebug(@"Update is missing view item");
                hasMalformedRowChange = YES;
            }
        }
    }];

    for (NSString *uniqueId in diffRemovedItemIds) {
        [self.viewItemCache removeObjectForKey:uniqueId];
    }

    if (hasMalformedRowChange) {
        // These errors seems to be very rare; they can only be reproduced
        // using the more extreme actions in the debug UI.
        OWSFailDebug(@"hasMalformedRowChange");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMappingWithSneakyTransaction];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    if (![self reloadViewItemsWithSneakyTransaction]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mapping.");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMappingWithSneakyTransaction];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewState.viewItems.count);

    // We may have filtered out some of the view items.
    // Ensure that these ids are culled from updatedItemSet.
    [updatedItemSet intersectSet:[NSSet setWithArray:self.viewState.interactionIndexMap.allKeys]];

    [self updateViewWithOldItemIdList:oldItemIdList updatedItemSet:updatedItemSet];
}

#pragma mark -

// A simpler version of the update logic we use when
// only transient items have changed.
- (void)updateForTransientItems
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    NSArray<NSString *> *oldItemIdList = self.viewState.interactionIds;

    if (![self reloadViewItemsWithSneakyTransaction]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mapping.");
        // resetMapping will call delegate.conversationViewModelDidUpdate.
        [self resetMappingWithSneakyTransaction];
        [self.delegate conversationViewModelDidReset];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewState.viewItems.count);

    [self updateViewWithOldItemIdList:oldItemIdList updatedItemSet:[NSSet set]];
}

- (ConversationUpdate *)conversationUpdateWithOldItemIdList:(NSArray<NSString *> *)oldItemIdList
                                             updatedItemSet:(NSSet<NSString *> *)updatedItemSetParam
{
    OWSAssertDebug(oldItemIdList);
    OWSAssertDebug(updatedItemSetParam);

    if (oldItemIdList.count != [NSSet setWithArray:oldItemIdList].count) {
        OWSFailDebug(@"Old view item list has duplicates.");
        return ConversationUpdate.reloadUpdate;
    }

    NSArray<NSString *> *newItemIdList = self.viewState.interactionIds;
    NSMutableDictionary<NSString *, id<ConversationViewItem>> *newViewItemMap = [NSMutableDictionary new];
    for (id<ConversationViewItem> viewItem in self.viewState.viewItems) {
        newViewItemMap[viewItem.itemId] = viewItem;
    }

    if (newItemIdList.count != [NSSet setWithArray:newItemIdList].count) {
        OWSFailDebug(@"New view item list has duplicates.");
        return ConversationUpdate.reloadUpdate;
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
            return ConversationUpdate.reloadUpdate;
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
            return ConversationUpdate.reloadUpdate;
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find inserted view item.");
            return ConversationUpdate.reloadUpdate;
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
        return ConversationUpdate.reloadUpdate;
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
            return ConversationUpdate.reloadUpdate;
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find holdover view item.");
            return ConversationUpdate.reloadUpdate;
        }
        if (viewItem.needsUpdate) {
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
            return ConversationUpdate.reloadUpdate;
        }
        NSUInteger newIndex = [newItemIdList indexOfObject:itemId];
        if (newIndex == NSNotFound) {
            OWSFailDebug(@"Can't find new index of updated view item.");
            return ConversationUpdate.reloadUpdate;
        }
        id<ConversationViewItem> _Nullable viewItem = newViewItemMap[itemId];
        if (!viewItem) {
            OWSFailDebug(@"Can't find inserted view item.");
            return ConversationUpdate.reloadUpdate;
        }
        [updateItems addObject:[[ConversationUpdateItem alloc] initWithUpdateItemType:ConversationUpdateItemType_Update
                                                                             oldIndex:oldIndex
                                                                             newIndex:newIndex
                                                                             viewItem:viewItem]];
    }

    BOOL shouldAnimateUpdates = [self shouldAnimateUpdateItems:updateItems
                                              oldViewItemCount:oldItemIdList.count
                                        updatedNeighborItemSet:updatedNeighborItemSet];

    return [ConversationUpdate diffUpdateWithUpdateItems:updateItems shouldAnimateUpdates:shouldAnimateUpdates];
}

- (void)updateViewWithOldItemIdList:(NSArray<NSString *> *)oldItemIdList
                     updatedItemSet:(NSSet<NSString *> *)updatedItemSetParam
{
    ConversationUpdate *conversationUpdate = [self conversationUpdateWithOldItemIdList:oldItemIdList
                                                                        updatedItemSet:updatedItemSetParam];
    return [self.delegate conversationViewModelDidUpdateWithSneakyTransaction:conversationUpdate];
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

// This is more expensive than incremental updates.
//
// We call `resetMapping` for two separate reasons:
//
// * Most of the time, we call `resetMapping` after a severe error to get back into a known good state.
//   We then call `conversationViewModelDidReset` to get the view back into a known good state (by
//   scrolling to the bottom).
// * We also call `resetMapping` to load an additional page of older message.  We very much _do not_
// want to change view scroll state in this case.
- (void)resetMappingWithSneakyTransaction
{
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self resetMappingWithTransaction:transaction];
    }];
}

- (void)resetMappingWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(self.messageMapping);

    self.collapseCutoffDate = [NSDate new];

    if (![self reloadViewItemsWithTransaction:transaction]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    // PERF TODO: don't call "reload" when appending new items, do a batch insert. Otherwise we re-render every cell.
    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate transaction:transaction];
}

#pragma mark - View Items

- (nullable NSIndexPath *)indexPathForViewItem:(id<ConversationViewItem>)viewItem
{
    return [self indexPathForInteractionId:viewItem.interaction.uniqueId];
}

- (nullable NSIndexPath *)indexPathForInteractionId:(NSString *)interactionId
{
    NSUInteger index = [self.viewState.viewItems indexOfObjectPassingTest:^BOOL(id<ConversationViewItem>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.interaction.uniqueId isEqualToString:interactionId];
    }];
    if (index == NSNotFound) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
}

- (void)ensureConversationProfileStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.conversationProfileState) {
        return;
    }

    // Many OWSProfileManager methods aren't safe to call from inside a database
    // transaction, so do this work now.
    //
    // TODO: It'd be nice if these methods took a transaction.
    BOOL hasLocalProfile = [self.profileManager hasLocalProfile];
    BOOL isThreadInProfileWhitelist = [self.profileManager isThreadInProfileWhitelist:self.thread
                                                                          transaction:transaction];
    BOOL hasUnwhitelistedMember = NO;
    for (SignalServiceAddress *address in self.thread.recipientAddresses) {
        if (![self.profileManager isUserInProfileWhitelist:address transaction:transaction]) {
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

// This is a key method.  It builds or rebuilds the list of
// cell view models.
//
// Returns NO on error.
- (BOOL)reloadViewItemsWithSneakyTransaction
{
    __block BOOL result;

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self reloadViewItemsWithTransaction:transaction];
    }];

    return result;
}

- (BOOL)reloadViewItemsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSMutableArray<id<ConversationViewItem>> *viewItems = [NSMutableArray new];
    NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache = [NSMutableDictionary new];

    [self ensureConversationProfileStateWithTransaction:transaction];

    ConversationStyle *conversationStyle = self.delegate.conversationStyle;

    _Nullable id<ConversationViewItem> (^createViewItemForInteraction)(TSInteraction *)
        = ^(TSInteraction *interaction) {
              OWSAssertDebug(interaction.uniqueId.length > 0);

              id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[interaction.uniqueId];
              if (!viewItem) {
                  viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:interaction
                                                                                   thread:self.thread
                                                                              transaction:transaction
                                                                        conversationStyle:conversationStyle];
              }
              OWSAssertDebug(!viewItemCache[interaction.uniqueId]);
              viewItemCache[interaction.uniqueId] = viewItem;

              if (viewItem && viewItem.messageCellType == OWSMessageCellType_StickerMessage
                  && viewItem.stickerAttachment == nil && !viewItem.isFailedSticker) {
                  return (id<ConversationViewItem>)nil;
              }

              return viewItem;
          };

    __block BOOL hasPlacedUnreadIndicator = NO;
    __block BOOL shouldShowDateOnNextViewItem = YES;
    __block uint64_t previousViewItemTimestamp = 0;
    void (^addHeaderViewItemIfNecessary)(id<ConversationViewItem>) = ^(id<ConversationViewItem> viewItem) {
        uint64_t viewItemTimestamp = viewItem.interaction.timestamp;
        OWSAssertDebug(viewItemTimestamp > 0);

        BOOL shouldShowDate = NO;
        if (previousViewItemTimestamp == 0) {
            // Only show for the first item if the date is not today
            shouldShowDateOnNextViewItem
                = ![DateUtil dateIsToday:[NSDate ows_dateWithMillisecondsSince1970:viewItemTimestamp]];
        } else if (![DateUtil isSameDayWithTimestamp:previousViewItemTimestamp timestamp:viewItemTimestamp]) {
            shouldShowDateOnNextViewItem = YES;
        }

        if (shouldShowDateOnNextViewItem && viewItem.canShowDate) {
            shouldShowDate = YES;
            shouldShowDateOnNextViewItem = NO;
        }

        TSInteraction *_Nullable interaction;

        if (!hasPlacedUnreadIndicator && !self.hasClearedUnreadMessagesIndicator
            && self.messageMapping.oldestUnreadInteraction != nil
            && self.messageMapping.oldestUnreadInteraction.sortId <= viewItem.interaction.sortId) {
            hasPlacedUnreadIndicator = YES;
            interaction = [[OWSUnreadIndicatorInteraction alloc] initWithThread:self.thread
                                                                      timestamp:viewItem.interaction.timestamp
                                                            receivedAtTimestamp:viewItem.interaction.receivedAtTimestamp
                                                                 shouldShowDate:shouldShowDate];
        } else if (shouldShowDate) {
            interaction = [[OWSDateHeaderInteraction alloc] initWithThread:self.thread
                                                                 timestamp:viewItem.interaction.timestamp];
        }

        if (interaction) {
            id<ConversationViewItem> _Nullable headerViewItem = createViewItemForInteraction(interaction);
            [headerViewItem clearNeedsUpdate];
            [viewItems addObject:headerViewItem];
        }

        previousViewItemTimestamp = viewItemTimestamp;
    };

    __block BOOL hasError = NO;
    _Nullable id<ConversationViewItem> (^tryToAddViewItemForInteraction)(TSInteraction *)
        = ^_Nullable id<ConversationViewItem>(TSInteraction *interaction)
    {
        OWSAssertDebug(interaction.uniqueId.length > 0);

        id<ConversationViewItem> _Nullable viewItem = createViewItemForInteraction(interaction);
        if (!viewItem) {
            return nil;
        }

        // Insert a dynamic header item before this item if necessary
        addHeaderViewItemIfNecessary(viewItem);

        [viewItem clearNeedsUpdate];
        [viewItems addObject:viewItem];

        return viewItem;
    };

    NSMutableSet<NSString *> *interactionIds = [NSMutableSet new];
    BOOL canLoadMoreItems = self.messageMapping.canLoadOlder;
    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];

    for (TSInteraction *interaction in self.messageMapping.loadedInteractions) {
        if (!interaction.uniqueId) {
            OWSFailDebug(@"invalid interaction in message mapping: %@.", interaction);
            // TODO: Add analytics.
            hasError = YES;
            continue;
        }
        [interactions addObject:interaction];
        if ([interactionIds containsObject:interaction.uniqueId]) {
            OWSFailDebug(@"Duplicate interaction(1): %@", interaction.uniqueId);
            continue;
        }
        [interactionIds addObject:interaction.uniqueId];
    }

    // Contact Offers / Thread Details are the first item in the thread
    if (self.shouldShowThreadDetails) {
        OWSLogDebug(@"adding thread details");
        OWSThreadDetailsInteraction *threadDetails =
            [[OWSThreadDetailsInteraction alloc] initWithThread:self.thread timestamp:NSDate.ows_millisecondTimeStamp];

        tryToAddViewItemForInteraction(threadDetails);
    }

    for (TSInteraction *interaction in interactions) {
        tryToAddViewItemForInteraction(interaction);
    }

    if (self.unsavedOutgoingMessages.count > 0) {
        for (TSOutgoingMessage *outgoingMessage in self.unsavedOutgoingMessages) {
            if ([interactionIds containsObject:outgoingMessage.uniqueId]) {
                OWSFailDebug(@"Duplicate interaction(2): %@", outgoingMessage.uniqueId);
                continue;
            }
            tryToAddViewItemForInteraction(outgoingMessage);
            [interactionIds addObject:outgoingMessage.uniqueId];
        }
    }

    if (self.typingIndicatorsSender) {
        OWSTypingIndicatorInteraction *typingIndicatorInteraction =
            [[OWSTypingIndicatorInteraction alloc] initWithThread:self.thread
                                                        timestamp:[NSDate ows_millisecondTimeStamp]
                                                          address:self.typingIndicatorsSender];
        tryToAddViewItemForInteraction(typingIndicatorInteraction);
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
        NSString *_Nullable accessibilityAuthorName = nil;

        OWSInteractionType interactionType = viewItem.interaction.interactionType;
        NSString *timestampText = [DateUtil formatTimestampShort:viewItem.interaction.timestamp];

        if (interactionType == OWSInteractionType_OutgoingMessage) {

            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
            MessageReceiptStatus receiptStatus =
                [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
            BOOL isDisappearingMessage = outgoingMessage.hasPerConversationExpiration;
            accessibilityAuthorName = NSLocalizedString(
                @"ACCESSIBILITY_LABEL_SENDER_SELF", @"Accessibility label for messages sent by you.");

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
                        && outgoingMessage.messageState != TSOutgoingMessageStateSending && !isDisappearingMessage);
            }

            // clustering
            if (previousViewItem == nil) {
                isFirstInCluster = YES;
            } else {
                isFirstInCluster = previousViewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage;
            }

            if (nextViewItem == nil) {
                isLastInCluster = YES;
            } else {
                isLastInCluster = nextViewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage;
            }
        } else if (interactionType == OWSInteractionType_IncomingMessage) {

            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)viewItem.interaction;
            SignalServiceAddress *incomingSenderAddress = incomingMessage.authorAddress;
            OWSAssertDebug(incomingSenderAddress.isValid);
            BOOL isDisappearingMessage = incomingMessage.hasPerConversationExpiration;
            accessibilityAuthorName = [self.contactsManager displayNameForAddress:incomingSenderAddress
                                                                      transaction:transaction];
            if (viewItem.interaction.interactionType == OWSInteractionType_ThreadDetails) {
                viewItem.senderUsername = [self.profileManager usernameForAddress:incomingSenderAddress
                                                                      transaction:transaction];
            }

            SignalServiceAddress *_Nullable nextIncomingSenderAddress = nil;
            if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                TSIncomingMessage *nextIncomingMessage = (TSIncomingMessage *)nextViewItem.interaction;
                nextIncomingSenderAddress = nextIncomingMessage.authorAddress;
                OWSAssertDebug(nextIncomingSenderAddress.isValid);
            }

            if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                NSString *nextTimestampText = [DateUtil formatTimestampShort:nextViewItem.interaction.timestamp];
                // We can skip the "incoming message status" footer in a cluster if the next message
                // has the same footer and no "date break" separates us.
                // ...but always show the "disappearing messages" animation.
                shouldHideFooter = ([timestampText isEqualToString:nextTimestampText]
                    && ((!incomingSenderAddress && !nextIncomingSenderAddress) ||
                        [incomingSenderAddress isEqualToAddress:nextIncomingSenderAddress])
                    && !isDisappearingMessage);
            }

            // clustering
            if (previousViewItem == nil) {
                isFirstInCluster = YES;
            } else if (previousViewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
                isFirstInCluster = YES;
            } else {
                TSIncomingMessage *previousIncomingMessage = (TSIncomingMessage *)previousViewItem.interaction;
                isFirstInCluster = ![incomingSenderAddress isEqualToAddress:previousIncomingMessage.authorAddress];
            }

            if (nextViewItem == nil) {
                isLastInCluster = YES;
            } else if (nextViewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
                isLastInCluster = YES;
            } else {
                TSIncomingMessage *nextIncomingMessage = (TSIncomingMessage *)nextViewItem.interaction;
                isLastInCluster = ![incomingSenderAddress isEqualToAddress:nextIncomingMessage.authorAddress];
            }

            if (viewItem.isGroupThread) {
                // Show the sender name for incoming group messages unless
                // the previous message has the same sender name and
                // no "date break" separates us.
                BOOL shouldShowSenderName = YES;
                if (previousViewItem && previousViewItem.interaction.interactionType == interactionType) {

                    TSIncomingMessage *previousIncomingMessage = (TSIncomingMessage *)previousViewItem.interaction;
                    SignalServiceAddress *previousIncomingSenderAddress = previousIncomingMessage.authorAddress;
                    OWSAssertDebug(previousIncomingSenderAddress.isValid);

                    shouldShowSenderName = ((!incomingSenderAddress && !previousIncomingSenderAddress)
                        || ![incomingSenderAddress isEqualToAddress:previousIncomingSenderAddress]);
                }
                if (shouldShowSenderName) {
                    senderName = [[NSAttributedString alloc] initWithString:accessibilityAuthorName];
                }

                // Show the sender avatar for incoming group messages unless
                // the next message has the same sender avatar and
                // no "date break" separates us.
                shouldShowSenderAvatar = YES;
                if (nextViewItem && nextViewItem.interaction.interactionType == interactionType) {
                    shouldShowSenderAvatar = ((!incomingSenderAddress && !nextIncomingSenderAddress)
                        || ![incomingSenderAddress isEqualToAddress:nextIncomingSenderAddress]);
                }
            }
        } else if (interactionType == OWSInteractionType_Info) {
            TSInfoMessage *infoMessage = (TSInfoMessage *)viewItem.interaction;
            if (infoMessage.messageType == TSInfoMessageProfileUpdate) {
                viewItem.senderProfileName = [self.profileManager fullNameForAddress:infoMessage.profileChangeAddress
                                                                         transaction:transaction];
            }
        }

        uint64_t collapseCutoffTimestamp = [NSDate ows_millisecondsSince1970ForDate:self.collapseCutoffDate];
        if (viewItem.interaction.receivedAtTimestamp > collapseCutoffTimestamp) {
            shouldHideFooter = NO;
        }

        viewItem.isFirstInCluster = isFirstInCluster;
        viewItem.isLastInCluster = isLastInCluster;
        viewItem.shouldShowSenderAvatar = shouldShowSenderAvatar;
        viewItem.shouldHideFooter = shouldHideFooter;
        viewItem.senderName = senderName;
        viewItem.accessibilityAuthorName = accessibilityAuthorName;
    }

    self.viewState = [[ConversationViewState alloc] initWithViewItems:viewItems
                                                       focusMessageId:self.focusMessageIdOnOpen];
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
- (void)reloadInteractionForViewItem:(id<ConversationViewItem>)viewItem transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    // This should never happen, but don't crash in production if we have a bug.
    if (!viewItem) {
        return;
    }

    TSInteraction *_Nullable interaction;
    if ([viewItem.interaction isKindOfClass:OWSThreadDetailsInteraction.class]) {
        // Thread details is not a persisted interaction.
        // It carries no mutable state, so there's no reason to reload it here.
        interaction = viewItem.interaction;
    } else {
        interaction = [TSInteraction anyFetchWithUniqueId:viewItem.interaction.uniqueId transaction:transaction];
    }

    if (!interaction) {
        OWSFailDebug(@"could not reload interaction");
    } else {
        [viewItem replaceInteraction:interaction transaction:transaction];
    }
}

- (nullable NSIndexPath *)ensureLoadWindowContainsQuotedReply:(OWSQuotedReplyModel *)quotedReply
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(quotedReply);
    OWSAssertDebug(quotedReply.timestamp > 0);
    OWSAssertDebug(quotedReply.authorAddress.isValid);

    if (quotedReply.isRemotelySourced) {
        return nil;
    }

    TSInteraction *quotedInteraction = [ThreadUtil findInteractionInThreadByTimestamp:quotedReply.timestamp
                                                                        authorAddress:quotedReply.authorAddress
                                                                       threadUniqueId:self.thread.uniqueId
                                                                          transaction:transaction];

    if (!quotedInteraction) {
        return nil;
    }

    return [self ensureLoadWindowContainsInteractionId:quotedInteraction.uniqueId transaction:transaction];
}

- (nullable NSIndexPath *)ensureLoadWindowContainsInteractionId:(NSString *)interactionId
                                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(interactionId);

    NSError *error;
    [self.messageMapping loadMessagePageAroundInteractionId:interactionId transaction:transaction error:&error];
    if (error != nil) {
        OWSFailDebug(@"failure: %@", error);
        return nil;
    }

    self.collapseCutoffDate = [NSDate new];

    if (![self reloadViewItemsWithTransaction:transaction]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate transaction:transaction];
    [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];

    NSIndexPath *_Nullable indexPath = [self indexPathForInteractionId:interactionId];
    if (indexPath == nil) {
        OWSFailDebug(@"indexPath was unexpectedly nil");
    }

    return indexPath;
}

- (void)ensureLoadWindowContainsNewestItemsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();

    NSError *error;
    [self.messageMapping loadNewestMessagePageWithTransaction:transaction error:&error];
    if (error != nil) {
        OWSFailDebug(@"failure: %@", error);
        return;
    }

    self.collapseCutoffDate = [NSDate new];

    if (![self reloadViewItemsWithTransaction:transaction]) {
        OWSFailDebug(@"failed to reload view items in resetMapping.");
    }

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate transaction:transaction];
    [self.delegate conversationViewModelRangeDidChangeWithTransaction:transaction];
}

- (void)typingIndicatorStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.thread);

    if (notification.object && ![notification.object isEqual:self.thread.uniqueId]) {
        return;
    }

    self.typingIndicatorsSender = [self.typingIndicators typingAddressForThread:self.thread];
}

- (void)setTypingIndicatorsSender:(nullable SignalServiceAddress *)typingIndicatorsSender
{
    OWSAssertIsOnMainThread();

    BOOL didChange = ![NSObject isNullableObject:typingIndicatorsSender equalTo:_typingIndicatorsSender];

    _typingIndicatorsSender = typingIndicatorsSender;

    // Update the view items if necessary.
    // We don't have to do this if they haven't been configured yet.
    if (didChange && self.viewState.viewItems != nil) {
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

- (nullable TSInteraction *)firstCallOrMessageForLoadedInteractionsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    for (TSInteraction *interaction in self.messageMapping.loadedInteractions) {
        switch (interaction.interactionType) {
            case OWSInteractionType_Unknown:
                OWSFailDebug(@"Unknown interaction type.");
                break;
            case OWSInteractionType_Call:
            case OWSInteractionType_IncomingMessage:
            case OWSInteractionType_OutgoingMessage:
                return interaction;
            case OWSInteractionType_Error:
            case OWSInteractionType_Info:
                break;
            case OWSInteractionType_ThreadDetails:
            case OWSInteractionType_TypingIndicator:
            case OWSInteractionType_UnreadIndicator:
            case OWSInteractionType_DateHeader:
                break;
        }
    }
    return nil;
}

- (BOOL)shouldShowThreadDetails
{
    return !self.canLoadOlderItems;
}

@end

NS_ASSUME_NONNULL_END
