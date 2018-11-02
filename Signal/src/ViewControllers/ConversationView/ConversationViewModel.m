//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewModel.h"
#import "ConversationViewItem.h"
#import "DateUtil.h"
#import "OWSMessageBubbleView.h"
#import "OWSQuotedReplyModel.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSUnreadIndicator.h>
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

NS_ASSUME_NONNULL_BEGIN

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
static const int kYapDatabasePageSize = 25;

// Never show more than n messages in conversation view when user arrives.
static const int kConversationInitialMaxRangeSize = 300;

// Never show more than n messages in conversation view at a time.
static const int kYapDatabaseRangeMaxLength = 25000;

static const int kYapDatabaseRangeMinLength = 0;

#pragma mark -

@interface ConversationViewModel ()

@property (nonatomic, weak) id<ConversationViewModelDelegate> delegate;

@property (nonatomic, readonly) TSThread *thread;

// The mapping must be updated in lockstep with the uiDatabaseConnection.
//
// * The first (required) step is to update uiDatabaseConnection using beginLongLivedReadTransaction.
// * The second (required) step is to update messageMappings.
// * The third (optional) step is to update the messageMappings range using
//   updateMessageMappingRangeOptions.
// * The fourth (optional) step is to update the view items using reloadViewItems.
// * The steps must be done in strict order.
// * If we do any of the steps, we must do all of the required steps.
// * We can't use messageMappings or viewItems after the first step until we've
//   done the last step; i.e.. we can't do any layout, since that uses the view
//   items which haven't been updated yet.
// * If the first and/or second steps changes the set of messages
//   their ordering and/or their state, we must do the third and fourth steps.
// * If we do the third step, we must call resetContentAndLayout afterward.
@property (nonatomic) YapDatabaseViewMappings *messageMappings;

@property (nonatomic) NSArray<id<ConversationViewItem>> *viewItems;
@property (nonatomic) NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache;

@property (nonatomic) NSUInteger lastRangeLength;
@property (nonatomic, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic, nullable) NSDate *collapseCutoffDate;
@property (nonatomic, nullable) NSString *typingIndicatorsSender;

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

#pragma mark

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
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ensureDynamicInteractions];
}

- (void)configure
{
    OWSLogInfo(@"");

    // We need to update the "unread indicator" _before_ we determine the initial range
    // size, since it depends on where the unread indicator is placed.
    self.lastRangeLength = 0;
    self.typingIndicatorsSender = [self.typingIndicators typingRecipientIdForThread:self.thread];

    [self ensureDynamicInteractions];
    [self.primaryStorage updateUIDatabaseConnectionToLatest];

    [self createNewMessageMappings];
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
}

- (void)viewDidLoad
{
    [self addNotificationListeners];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)canLoadMoreItems
{
    if (self.lastRangeLength >= kYapDatabaseRangeMaxLength) {
        return NO;
    }

    NSUInteger loadWindowSize = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    __block NSUInteger totalMessageCount;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        totalMessageCount =
            [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];
    return loadWindowSize < totalMessageCount;
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

    [self loadNMoreMessages:kYapDatabasePageSize];

    // Don’t auto-scroll after “loading more messages” unless we have “more unseen messages”.
    //
    // Otherwise, tapping on "load more messages" autoscrolls you downward which is completely wrong.
    if (hasEarlierUnseenMessages && !self.focusMessageIdOnOpen) {
        // Ensure view items are updated before trying to scroll to the
        // unread indicator.
        //
        // loadNMoreMessages calls resetMappings which calls ensureDynamicInteractions,
        // which may move the unread indicator, and for scrollToUnreadIndicatorAnimated
        // to work properly, the view items need to be updated to reflect that change.
        [self.primaryStorage updateUIDatabaseConnectionToLatest];

        [self.delegate conversationViewModelDidLoadPrevPage];
    }
}

- (void)loadNMoreMessages:(NSUInteger)numberOfMessagesToLoad
{
    [self.delegate conversationViewModelWillLoadMoreItems];

    self.lastRangeLength = MIN(self.lastRangeLength + numberOfMessagesToLoad, (NSUInteger)kYapDatabaseRangeMaxLength);

    [self resetMappings];

    [self.delegate conversationViewModelDidLoadMoreItems];
}

- (void)updateMessageMappingRangeOptions
{
    NSUInteger rangeLength = 0;

    if (self.lastRangeLength == 0) {
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
    }

    // Always try to load at least a single page of messages.
    rangeLength = MAX(rangeLength, kYapDatabasePageSize);

    // Range size should monotonically increase.
    rangeLength = MAX(rangeLength, self.lastRangeLength);

    // Enforce max range size.
    rangeLength = MIN(rangeLength, kYapDatabaseRangeMaxLength);

    self.lastRangeLength = rangeLength;

    YapDatabaseViewRangeOptions *rangeOptions =
        [YapDatabaseViewRangeOptions flexibleRangeWithLength:rangeLength offset:0 from:YapDatabaseViewEnd];

    rangeOptions.maxLength = MAX(rangeLength, kYapDatabaseRangeMaxLength);
    rangeOptions.minLength = kYapDatabaseRangeMinLength;

    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
    [self.delegate conversationViewModelRangeDidChange];
    self.collapseCutoffDate = [NSDate new];
}

- (void)ensureDynamicInteractions
{
    OWSAssertIsOnMainThread();

    const int currentMaxRangeSize = (int)self.lastRangeLength;
    const int maxRangeSize = MAX(kConversationInitialMaxRangeSize, currentMaxRangeSize);

    self.dynamicInteractions = [ThreadUtil ensureDynamicInteractionsForThread:self.thread
                                                              contactsManager:self.contactsManager
                                                              blockingManager:self.blockingManager
                                                                 dbConnection:self.editingDatabaseConnection
                                                  hideUnreadMessagesIndicator:self.hasClearedUnreadMessagesIndicator
                                                          lastUnreadIndicator:self.dynamicInteractions.unreadIndicator
                                                               focusMessageId:self.focusMessageIdOnOpen
                                                                 maxRangeSize:maxRangeSize];
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
        [self ensureDynamicInteractions];
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

    // External database modifications can't be converted into incremental updates,
    // so rebuild everything.  This is expensive and usually isn't necessary, but
    // there's no alternative.
    //
    // We don't need to do this if we're not observing db modifications since we'll
    // do it when we resume.
    [self resetMappings];
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

    NSArray *notifications = notification.userInfo[OWSUIDatabaseConnectionNotificationsKey];
    OWSAssertDebug([notifications isKindOfClass:[NSArray class]]);

    if (![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] hasChangesForGroup:self.thread.uniqueId
                                                                                inNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];

        [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate];
        return;
    }

    NSArray<YapDatabaseViewSectionChange *> *sectionChanges = nil;
    NSArray<YapDatabaseViewRowChange *> *rowChanges = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                               rowChanges:&rowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];

    if ([sectionChanges count] == 0 && [rowChanges count] == 0) {
        // YapDatabase will ignore insertions within the message mapping's
        // range that are not within the current mapping's contents.  We
        // may need to extend the mapping's contents to reflect the current
        // range.
        [self updateMessageMappingRangeOptions];
        return [self.delegate conversationViewModelDidUpdate:ConversationUpdate.minorUpdate];
    }

    NSMutableArray<NSString *> *oldItemIdList = [NSMutableArray new];
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [oldItemIdList addObject:viewItem.itemId];
    }

    // We need to reload any modified interactions _before_ we call
    // reloadViewItems.
    BOOL hasMalformedRowChange = NO;
    NSMutableSet<NSString *> *updatedItemSet = [NSMutableSet new];
    NSMutableSet<NSString *> *updatedNeighborItemSet = [NSMutableSet new];
    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeUpdate: {
                YapCollectionKey *collectionKey = rowChange.collectionKey;
                if (collectionKey.key) {
                    id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[collectionKey.key];
                    if (viewItem) {
                        [self reloadInteractionForViewItem:viewItem];
                        [updatedItemSet addObject:viewItem.itemId];
                        if (rowChange.changes == YapDatabaseViewChangedDependency) {
                            [updatedNeighborItemSet addObject:viewItem.itemId];
                        }
                    } else {
                        hasMalformedRowChange = YES;
                    }
                } else if (rowChange.indexPath && rowChange.originalIndex < self.viewItems.count) {
                    // Do nothing, this is a pseudo-update generated due to
                    // setCellDrawingDependencyOffsets.
                    OWSAssertDebug(rowChange.changes == YapDatabaseViewChangedDependency);
                } else {
                    hasMalformedRowChange = YES;
                }
                break;
            }
            case YapDatabaseViewChangeDelete: {
                // Discard cached view items after deletes.
                YapCollectionKey *collectionKey = rowChange.collectionKey;
                if (collectionKey.key) {
                    [self.viewItemCache removeObjectForKey:collectionKey.key];
                } else {
                    hasMalformedRowChange = YES;
                }
                break;
            }
            default:
                break;
        }
        if (hasMalformedRowChange) {
            break;
        }
    }

    if (hasMalformedRowChange) {
        // These errors seems to be very rare; they can only be reproduced
        // using the more extreme actions in the debug UI.
        OWSFailDebug(@"hasMalformedRowChange");
        // resetMappings will call delegate.conversationViewModelDidUpdate.
        [self resetMappings];
        return;
    }

    if (![self reloadViewItems]) {
        // These errors are rare.
        OWSFailDebug(@"could not reload view items; hard resetting message mappings.");
        // resetMappings will call delegate.conversationViewModelDidUpdate.
        [self resetMappings];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewItems.count);

    [self updateViewWithOldItemIdList:oldItemIdList
                       updatedItemSet:updatedItemSet
               updatedNeighborItemSet:updatedNeighborItemSet];
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
        OWSFailDebug(@"could not reload view items; hard resetting message mappings.");
        // resetMappings will call delegate.conversationViewModelDidUpdate.
        [self resetMappings];
        return;
    }

    OWSLogVerbose(@"self.viewItems.count: %zd -> %zd", oldItemIdList.count, self.viewItems.count);

    [self updateViewWithOldItemIdList:oldItemIdList updatedItemSet:[NSSet set] updatedNeighborItemSet:nil];
}

- (void)updateViewWithOldItemIdList:(NSArray<NSString *> *)oldItemIdList
                     updatedItemSet:(NSSet<NSString *> *)updatedItemSet
             updatedNeighborItemSet:(nullable NSMutableSet<NSString *> *)updatedNeighborItemSet
{
    OWSAssertDebug(oldItemIdList);
    OWSAssertDebug(updatedItemSet);

    if (!self.delegate.isObservingVMUpdates) {
        OWSFailDebug(@"Skipping VM update.");
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
    NSMutableSet<NSString *> *deletedItemIdSet = [oldItemIdSet mutableCopy];
    [deletedItemIdSet minusSet:newItemIdSet];
    NSMutableSet<NSString *> *insertedItemIdSet = [newItemIdSet mutableCopy];
    [insertedItemIdSet minusSet:oldItemIdSet];
    NSArray<NSString *> *deletedItemIdList = [deletedItemIdSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *insertedItemIdList =
        [insertedItemIdSet.allObjects sortedArrayUsingSelector:@selector(compare:)];

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
                if (([viewItem.interaction isKindOfClass:[TSIncomingMessage class]] ||
                        [viewItem.interaction isKindOfClass:[TSOutgoingMessage class]])
                    && updateItem.newIndex >= oldViewItemCount) {
                    continue;
                }
                isOnlyModifyingLastMessage = NO;
                break;
            }
            case ConversationUpdateItemType_Update: {
                id<ConversationViewItem> viewItem = updateItem.viewItem;
                if ([updatedNeighborItemSet containsObject:viewItem.itemId]) {
                    continue;
                }
                OWSAssertDebug(viewItem);
                if (([viewItem.interaction isKindOfClass:[TSIncomingMessage class]] ||
                        [viewItem.interaction isKindOfClass:[TSOutgoingMessage class]])
                    && updateItem.newIndex >= oldViewItemCount) {
                    continue;
                }
                isOnlyModifyingLastMessage = NO;
                break;
            }
        }
    }
    BOOL shouldAnimateRowUpdates = !isOnlyModifyingLastMessage;
    return shouldAnimateRowUpdates;
}

- (void)createNewMessageMappings
{
    if (self.thread.uniqueId.length > 0) {
        self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ self.thread.uniqueId ]
                                                                          view:TSMessageDatabaseViewExtensionName];
    } else {
        OWSFailDebug(@"uniqueId unexpectedly empty for thread: %@", self.thread);
        self.messageMappings =
            [[YapDatabaseViewMappings alloc] initWithGroups:@[] view:TSMessageDatabaseViewExtensionName];
    }

    // Cells' appearance can depend on adjacent cells in both directions.
    //
    // TODO: We could do the same thing in our logic to generate "update items"
    //       in updateViewWithOldItemIdList.
    [self.messageMappings setCellDrawingDependencyOffsets:[NSSet setWithArray:@[
        @(-1),
        @(+1),
    ]]
                                                 forGroup:self.thread.uniqueId];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    // We need to impose the range restrictions on the mappings immediately to avoid
    // doing a great deal of unnecessary work and causing a perf hotspot.
    [self updateMessageMappingRangeOptions];
}

- (void)resetMappings
{
    OWSAssertDebug(self.messageMappings);

    if (self.messageMappings != nil) {
        // Make sure our mapping and range state is up-to-date.
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];
        [self updateMessageMappingRangeOptions];
    }
    self.collapseCutoffDate = [NSDate new];

    [self ensureDynamicInteractions];

    // There appears to be a bug in YapDatabase that sometimes delays modifications
    // made in another process (e.g. the SAE) from showing up in other processes.
    // There's a simple workaround: a trivial write to the database flushes changes
    // made from other processes.
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[NSUUID UUID].UUIDString forKey:@"conversation_view_noop_mod" inCollection:@"temp"];
    }];

    [self.delegate conversationViewModelDidUpdate:ConversationUpdate.reloadUpdate];
}

#pragma mark - View Items

// This is a key method.  It builds or rebuilds the list of
// cell view models.
//
// Returns NO on error.
- (BOOL)reloadViewItems
{
    NSMutableArray<id<ConversationViewItem>> *viewItems = [NSMutableArray new];
    NSMutableDictionary<NSString *, id<ConversationViewItem>> *viewItemCache = [NSMutableDictionary new];

    NSUInteger count = [self.messageMappings numberOfItemsInSection:0];
    BOOL isGroupThread = self.thread.isGroupThread;
    ConversationStyle *conversationStyle = self.delegate.conversationStyle;

    __block BOOL hasError = NO;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssertDebug(viewTransaction);
        for (NSUInteger row = 0; row < count; row++) {
            TSInteraction *interaction =
                [viewTransaction objectAtRow:row inSection:0 withMappings:self.messageMappings];
            if (!interaction) {
                OWSFailDebug(
                    @"missing interaction in message mappings: %lu / %lu.", (unsigned long)row, (unsigned long)count);
                // TODO: Add analytics.
                hasError = YES;
                continue;
            }
            if (!interaction.uniqueId) {
                OWSFailDebug(@"invalid interaction in message mappings: %lu / %lu: %@.",
                    (unsigned long)row,
                    (unsigned long)count,
                    interaction);
                // TODO: Add analytics.
                hasError = YES;
                continue;
            }

            id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[interaction.uniqueId];
            if (!viewItem) {
                viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:interaction
                                                                          isGroupThread:isGroupThread
                                                                            transaction:transaction
                                                                      conversationStyle:conversationStyle];
            }
            [viewItems addObject:viewItem];
            OWSAssertDebug(!viewItemCache[interaction.uniqueId]);
            viewItemCache[interaction.uniqueId] = viewItem;
        }

        if (self.typingIndicatorsSender) {
            id<ConversationViewItem> _Nullable lastViewItem = viewItems.lastObject;
            uint64_t typingIndicatorTimestamp = (lastViewItem ? lastViewItem.interaction.timestamp + 1 : 1);
            TSInteraction *interaction =
                [[OWSTypingIndicatorInteraction alloc] initWithThread:self.thread
                                                            timestamp:typingIndicatorTimestamp
                                                          recipientId:self.typingIndicatorsSender];
            id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[interaction.uniqueId];
            if (!viewItem) {
                viewItem = [[ConversationInteractionViewItem alloc] initWithInteraction:interaction
                                                                          isGroupThread:isGroupThread
                                                                            transaction:transaction
                                                                      conversationStyle:conversationStyle];
            }
            [viewItems addObject:viewItem];
            OWSAssertDebug(!viewItemCache[interaction.uniqueId]);
            viewItemCache[interaction.uniqueId] = viewItem;
        }
    }];

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

        uint64_t viewItemTimestamp = viewItem.interaction.timestampForSorting;
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

            unreadIndicator =
                [[OWSUnreadIndicator alloc] initUnreadIndicatorWithTimestamp:viewItem.interaction.timestamp
                                                       hasMoreUnseenMessages:NO
                                        missingUnseenSafetyNumberChangeCount:0
                                                     unreadIndicatorPosition:0
                                             firstUnseenInteractionTimestamp:viewItem.interaction.timestamp];
        }

        // Place the unread indicator onto the first appropriate view item,
        // if any.
        if (unreadIndicator && viewItem.interaction.timestampForSorting >= unreadIndicator.timestamp) {
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

        if (viewItem.interaction.timestampForSorting > collapseCutoffTimestamp) {
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

    // TODO:
    // We try to find the index of the item within the current thread's
    // interactions that includes the "quoted interaction".
    //
    // NOTE: There are two indices:
    //
    // * The "group index" of the member of the database views group at
    //   the db conneciton's current checkpoint.
    // * The "index row/section" in the message mapping.
    //
    // NOTE: Since the range _IS NOT_ filtered by author,
    // and timestamp collisions are possible, it's possible
    // for:
    //
    // * The range to include more than the "quoted interaction".
    // * The range to be non-empty but NOT include the "quoted interaction",
    //   although this would be a bug.
    __block TSInteraction *_Nullable quotedInteraction;
    __block NSUInteger threadInteractionCount = 0;
    __block NSNumber *_Nullable groupIndex = nil;

    if (quotedReply.isRemotelySourced) {
        return nil;
    }

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        quotedInteraction = [ThreadUtil findInteractionInThreadByTimestamp:quotedReply.timestamp
                                                                  authorId:quotedReply.authorId
                                                            threadUniqueId:self.thread.uniqueId
                                                               transaction:transaction];
        if (!quotedInteraction) {
            return;
        }

        YapDatabaseAutoViewTransaction *_Nullable extension =
            [transaction extension:TSMessageDatabaseViewExtensionName];
        if (!extension) {
            OWSFailDebug(@"Couldn't load view.");
            return;
        }

        threadInteractionCount = [extension numberOfItemsInGroup:self.thread.uniqueId];

        groupIndex = [self findGroupIndexOfThreadInteraction:quotedInteraction transaction:transaction];
    }];

    if (!quotedInteraction || !groupIndex) {
        return nil;
    }

    NSUInteger indexRow = 0;
    NSUInteger indexSection = 0;
    BOOL isInMappings = [self.messageMappings getRow:&indexRow
                                             section:&indexSection
                                            forIndex:groupIndex.unsignedIntegerValue
                                             inGroup:self.thread.uniqueId];

    if (!isInMappings) {
        NSInteger desiredWindowSize = MAX(0, 1 + (NSInteger)threadInteractionCount - groupIndex.integerValue);
        NSUInteger oldLoadWindowSize = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
        NSInteger additionalItemsToLoad = MAX(0, desiredWindowSize - (NSInteger)oldLoadWindowSize);
        if (additionalItemsToLoad < 1) {
            OWSLogError(@"Couldn't determine how to load quoted reply.");
            return nil;
        }

        // Try to load more messages so that the quoted message
        // is in the load window.
        //
        // This may fail if the quoted message is very old, in which
        // case we'll load the max number of messages.
        [self loadNMoreMessages:(NSUInteger)additionalItemsToLoad];

        // `loadNMoreMessages` will reset the mapping and possibly
        // integrate new changes, so we need to reload the "group index"
        // of the quoted message.
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            groupIndex = [self findGroupIndexOfThreadInteraction:quotedInteraction transaction:transaction];
        }];

        if (!quotedInteraction || !groupIndex) {
            OWSLogError(@"Failed to find quoted reply in group.");
            return nil;
        }

        isInMappings = [self.messageMappings getRow:&indexRow
                                            section:&indexSection
                                           forIndex:groupIndex.unsignedIntegerValue
                                            inGroup:self.thread.uniqueId];

        if (!isInMappings) {
            OWSLogError(@"Could not load quoted reply into mapping.");
            return nil;
        }
    }

    // The mapping indices and view item indices don't always align for corrupt mappings.
    __block TSInteraction *_Nullable interaction;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssertDebug(viewTransaction);
        interaction = [viewTransaction objectAtRow:indexRow inSection:indexSection withMappings:self.messageMappings];
    }];
    if (!interaction) {
        OWSFailDebug(@"Could not locate interaction for quoted reply.");
        return nil;
    }
    id<ConversationViewItem> _Nullable viewItem = self.viewItemCache[interaction.uniqueId];
    if (!viewItem) {
        OWSFailDebug(@"Could not locate view item for quoted reply.");
        return nil;
    }
    NSUInteger viewItemIndex = [self.viewItems indexOfObject:viewItem];
    if (viewItemIndex == NSNotFound) {
        OWSFailDebug(@"Could not locate view item index for quoted reply.");
        return nil;
    }
    return [NSIndexPath indexPathForRow:(NSInteger)viewItemIndex inSection:0];
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
    OWSAssertDebug([notification.object isKindOfClass:[NSString class]]);
    OWSAssertDebug(self.thread);

    if (![notification.object isEqual:self.thread.uniqueId]) {
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
        [self updateForTransientItems];
    }
}

@end

NS_ASSUME_NONNULL_END
