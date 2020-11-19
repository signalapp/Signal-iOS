//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "NSString+SSK.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadTracking.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInteraction.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSOutgoingMessage.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

BOOL IsNoteToSelfEnabled(void)
{
    return YES;
}

@interface TSThread ()

@property (nonatomic) NSDate *creationDate;
@property (nonatomic, nullable) NSNumber *archivedAsOfMessageSortId;
@property (nonatomic, copy, nullable) NSString *messageDraft;
@property (atomic, nullable) NSDate *mutedUntilDate;

// DEPRECATED - not used since migrating to sortId
// but keeping these properties around to ease any pain in the back-forth
// migration while testing. Eventually we can safely delete these as they aren't used anywhere.
@property (nonatomic, nullable) NSDate *lastMessageDate DEPRECATED_ATTRIBUTE;
@property (nonatomic, nullable) NSDate *archivalDate DEPRECATED_ATTRIBUTE;

@end

#pragma mark -

@implementation TSThread

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

+ (NSString *)collection {
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId
{
    self = [super initWithUniqueId:uniqueId];

    if (self) {
        _creationDate    = [NSDate date];
        _messageDraft    = nil;
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // renamed `hasEverHadMessage` -> `shouldThreadBeVisible`
    if (!_shouldThreadBeVisible) {
        NSNumber *_Nullable legacy_hasEverHadMessage = [coder decodeObjectForKey:@"hasEverHadMessage"];

        if (legacy_hasEverHadMessage != nil) {
            _shouldThreadBeVisible = legacy_hasEverHadMessage.boolValue;
        }
    }

    NSDate *_Nullable lastMessageDate = [coder decodeObjectOfClass:NSDate.class forKey:@"lastMessageDate"];
    NSDate *_Nullable archivalDate = [coder decodeObjectOfClass:NSDate.class forKey:@"archivalDate"];
    _isArchivedByLegacyTimestampForSorting =
        [self.class legacyIsArchivedWithLastMessageDate:lastMessageDate archivalDate:archivalDate];

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];
    
    [SSKPreferences setHasSavedThreadWithValue:YES transaction:transaction];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self removeAllThreadInteractionsWithTransaction:transaction];

    [super removeWithTransaction:transaction];
}

- (void)removeAllThreadInteractionsWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // We can't safely delete interactions while enumerating them, so
    // we collect and delete separately.
    //
    // We don't want to instantiate the interactions when collecting them
    // or when deleting them.
    NSMutableArray<NSString *> *interactionIds = [NSMutableArray new];
    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    OWSAssertDebug(interactionsByThread);
    __block BOOL didDetectCorruption = NO;
    [interactionsByThread enumerateKeysInGroup:self.uniqueId
                                    usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
                                        if (![key isKindOfClass:[NSString class]] || key.length < 1) {
                                            OWSFailDebug(
                                                @"invalid key in thread interactions: %@, %@.", key, [key class]);
                                            didDetectCorruption = YES;
                                            return;
                                        }
                                        [interactionIds addObject:key];
                                    }];

    if (didDetectCorruption) {
        OWSLogWarn(@"incrementing version of: %@", TSMessageDatabaseViewExtensionName);
        [OWSPrimaryStorage incrementVersionOfDatabaseExtension:TSMessageDatabaseViewExtensionName];
    }

    for (NSString *interactionId in interactionIds) {
        // We need to fetch each interaction, since [TSInteraction removeWithTransaction:] does important work.
        TSInteraction *_Nullable interaction =
            [TSInteraction fetchObjectWithUniqueID:interactionId transaction:transaction];
        if (!interaction) {
            OWSFailDebug(@"couldn't load thread's interaction for deletion.");
            continue;
        }
        [interaction removeWithTransaction:transaction];
    }
}

- (BOOL)isNoteToSelf
{
    if (!IsNoteToSelfEnabled()) { return NO; }
    if (![self isKindOfClass:TSContactThread.class]) { return NO; }
    return [self.contactIdentifier isEqual:OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey];
}

#pragma mark - To be subclassed.

- (BOOL)isGroupThread {
    OWSAbstractMethod();

    return NO;
}

// Override in ContactThread
- (nullable NSString *)contactIdentifier
{
    return nil;
}

- (NSString *)name {
    OWSAbstractMethod();

    return nil;
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    OWSAbstractMethod();

    return @[];
}

#pragma mark - Interactions

/**
 * Iterate over this thread's interactions
 */
- (void)enumerateInteractionsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                  usingBlock:(void (^)(TSInteraction *interaction,
                                                 YapDatabaseReadTransaction *transaction))block
{
    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    [interactionsByThread
        enumerateKeysAndObjectsInGroup:self.uniqueId
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                TSInteraction *interaction = object;
                                block(interaction, transaction);
                            }];
}

/**
 * Enumerates all the threads interactions. Note this will explode if you try to create a transaction in the block.
 * If you need a transaction, use the sister method: `enumerateInteractionsWithTransaction:usingBlock`
 */
- (void)enumerateInteractionsUsingBlock:(void (^)(TSInteraction *interaction))block
{
    [self.dbReadWriteConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self enumerateInteractionsWithTransaction:transaction
                                        usingBlock:^(
                                            TSInteraction *interaction, YapDatabaseReadTransaction *t) {

                                            block(interaction);
                                        }];
    }];
}

- (TSInteraction *)lastInteraction
{
    __block TSInteraction *interaction;
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [self getLastInteractionWithTransaction:transaction];
    }];
    return interaction;
}

- (TSInteraction *)getLastInteractionWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    YapDatabaseViewTransaction *interactions = [transaction ext:TSMessageDatabaseViewExtensionName];
    return [interactions lastObjectInGroup:self.uniqueId];
}

/**
 * Useful for tests and debugging. In production use an enumeration method.
 */
- (NSArray<TSInteraction *> *)allInteractions
{
    NSMutableArray<TSInteraction *> *interactions = [NSMutableArray new];
    [self enumerateInteractionsUsingBlock:^(TSInteraction *interaction) {
        [interactions addObject:interaction];
    }];

    return [interactions copy];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *)receivedMessagesForInvalidKey:(NSData *)key
{
    NSMutableArray *errorMessages = [NSMutableArray new];
    [self enumerateInteractionsUsingBlock:^(TSInteraction *interaction) {
        if ([interaction isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
            TSInvalidIdentityKeyReceivingErrorMessage *error = (TSInvalidIdentityKeyReceivingErrorMessage *)interaction;
            @try {
                if ([[error throws_newIdentityKey] isEqualToData:key]) {
                    [errorMessages addObject:(TSInvalidIdentityKeyReceivingErrorMessage *)interaction];
                }
            } @catch (NSException *exception) {
                OWSFailDebug(@"exception: %@", exception);
            }
        }
    }];

    return [errorMessages copy];
}
#pragma clang diagnostic pop

- (NSUInteger)numberOfInteractions
{
    __block NSUInteger count;
    [[self dbReadConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
        count = [interactionsByThread numberOfItemsInGroup:self.uniqueId];
    }];
    return count;
}

- (NSArray<id<OWSReadTracking>> *)unseenMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<id<OWSReadTracking>> *messages = [NSMutableArray new];
    [[TSDatabaseView unseenDatabaseViewExtension:transaction]
        enumerateKeysAndObjectsInGroup:self.uniqueId
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                                    OWSFailDebug(@"Unexpected object in unseen messages: %@", [object class]);
                                    return;
                                }
                                id<OWSReadTracking> unread = (id<OWSReadTracking>)object;
                                if (unread.read) {
                                    NSLog(@"Found an already read message in the * unseen * messages list.");
                                    return;
                                }
                                [messages addObject:unread];
                            }];

    return [messages copy];
}

- (NSUInteger)unreadMessageCountWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    __block NSUInteger count = 0;

    YapDatabaseViewTransaction *unreadMessages = [transaction ext:TSUnreadDatabaseViewExtensionName];
    [unreadMessages enumerateKeysAndObjectsInGroup:self.uniqueId
                                        usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
        if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
            OWSFailDebug(@"Unexpected object in unread messages: %@", [object class]);
            return;
        }
        id<OWSReadTracking> unread = (id<OWSReadTracking>)object;
        if (unread.read) {
            NSLog(@"Found an already read message in the * unread * messages list.");
            return;
        }
        count += 1;
    }];

    return count;
}

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    for (id<OWSReadTracking> message in [self unseenMessagesWithTransaction:transaction]) {
        [message markAsReadAtTimestamp:[NSDate ows_millisecondTimeStamp] sendReadReceipt:YES transaction:transaction];
    }

    // Just to be defensive, we'll also check for unread messages.
    OWSAssertDebug([self unseenMessagesWithTransaction:transaction].count < 1);
}

- (nullable TSInteraction *)lastInteractionForInboxWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    __block NSUInteger missedCount = 0;
    __block TSInteraction *last = nil;
    [[transaction ext:TSMessageDatabaseViewExtensionName]
        enumerateKeysAndObjectsInGroup:self.uniqueId
                           withOptions:NSEnumerationReverse
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                OWSAssertDebug([object isKindOfClass:[TSInteraction class]]);

                                missedCount++;
                                TSInteraction *interaction = (TSInteraction *)object;

                                if ([TSThread shouldInteractionAppearInInbox:interaction]) {
                                    last = interaction;

                                    // For long ignored threads, with lots of SN changes this can get really slow.
                                    // I see this in development because I have a lot of long forgotten threads with
                                    // members who's test devices are constantly reinstalled. We could add a
                                    // purpose-built DB view, but I think in the real world this is rare to be a
                                    // hotspot.
                                    if (missedCount > 50) {
                                        OWSLogWarn(@"found last interaction for inbox after skipping %lu items",
                                            (unsigned long)missedCount);
                                    }
                                    *stop = YES;
                                }
                            }];
    return last;
}

- (NSString *)lastMessageTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSInteraction *interaction = [self lastInteractionForInboxWithTransaction:transaction];
    if ([interaction conformsToProtocol:@protocol(OWSPreviewText)]) {
        id<OWSPreviewText> previewable = (id<OWSPreviewText>)interaction;
        return [previewable previewTextWithTransaction:transaction].filterStringForDisplay;
    } else {
        return @"";
    }
}

// Returns YES IFF the interaction should show up in the inbox as the last message.
+ (BOOL)shouldInteractionAppearInInbox:(TSInteraction *)interaction
{
    OWSAssertDebug(interaction);

    if (interaction.isDynamicInteraction) {
        return NO;
    }

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
        if (errorMessage.errorType == TSErrorMessageNonBlockingIdentityChange) {
            // Otherwise all group threads with the recipient will percolate to the top of the inbox, even though
            // there was no meaningful interaction.
            return NO;
        }
    }

    return YES;
}

- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssertDebug(lastMessage);
    OWSAssertDebug(transaction);

    if (![self.class shouldInteractionAppearInInbox:lastMessage]) {
        return;
    }

    if (!self.shouldThreadBeVisible) {
        self.shouldThreadBeVisible = YES;
        [self saveWithTransaction:transaction];
    } else {
        [self touchWithTransaction:transaction];
    }
}

#pragma mark - Disappearing Messages

- (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfigurationWithTransaction:
    (YapDatabaseReadTransaction *)transaction
{
    return [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThreadId:self.uniqueId transaction:transaction];
}

- (uint32_t)disappearingMessagesDurationWithTransaction:(YapDatabaseReadTransaction *)transaction
{

    OWSDisappearingMessagesConfiguration *config = [self disappearingMessagesConfigurationWithTransaction:transaction];

    if (!config.isEnabled) {
        return 0;
    } else {
        return config.durationSeconds;
    }
}

#pragma mark - Archival

- (BOOL)isArchivedWithTransaction:(YapDatabaseReadTransaction *)transaction;
{
    if (!self.archivedAsOfMessageSortId) {
        return NO;
    }

    TSInteraction *_Nullable latestInteraction = [self lastInteractionForInboxWithTransaction:transaction];
    uint64_t latestSortIdForInbox = latestInteraction ? latestInteraction.sortId : 0;
    return self.archivedAsOfMessageSortId.unsignedLongLongValue >= latestSortIdForInbox;
}

+ (BOOL)legacyIsArchivedWithLastMessageDate:(nullable NSDate *)lastMessageDate
                               archivalDate:(nullable NSDate *)archivalDate
{
    if (!archivalDate) {
        return NO;
    }

    if (!lastMessageDate) {
        return YES;
    }

    return [archivalDate compare:lastMessageDate] != NSOrderedAscending;
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSThread *thread) {
                                 uint64_t latestId = [SSKIncrementingIdFinder previousIdWithKey:TSInteraction.collection
                                                                                    transaction:transaction];
                                 thread.archivedAsOfMessageSortId = @(latestId);
                             }];

    [self markAllAsReadWithTransaction:transaction];
}

- (void)unarchiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSThread *thread) {
                                 thread.archivedAsOfMessageSortId = nil;
                             }];
}

#pragma mark - Drafts

- (NSString *)currentDraftWithTransaction:(YapDatabaseReadTransaction *)transaction {
    TSThread *thread = [TSThread fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    if (thread.messageDraft) {
        return thread.messageDraft;
    } else {
        return @"";
    }
}

- (void)setDraft:(NSString *)draftString transaction:(YapDatabaseReadWriteTransaction *)transaction {
    TSThread *thread    = [TSThread fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    thread.messageDraft = draftString;
    [thread saveWithTransaction:transaction];
}

#pragma mark - Muted

- (BOOL)isMuted
{
    NSDate *mutedUntilDate = self.mutedUntilDate;
    NSDate *now = [NSDate date];
    return (mutedUntilDate != nil &&
            [mutedUntilDate timeIntervalSinceDate:now] > 0);
}

- (void)updateWithMutedUntilDate:(NSDate *)mutedUntilDate transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSThread *thread) {
                                 [thread setMutedUntilDate:mutedUntilDate];
                             }];
}

@end

NS_ASSUME_NONNULL_END
