//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

BOOL IsNoteToSelfEnabled(void)
{
    return YES;
}

@interface TSThread ()

@property (nonatomic) NSDate *creationDate;
@property (nonatomic, nullable) NSDate *lastInteractionDate;
@property (nonatomic, nullable) NSNumber *archivedAsOfMessageSortId;
@property (nonatomic, copy, nullable) NSString *messageDraft;
@property (atomic, nullable) NSDate *mutedUntilDate;

@end

@implementation TSThread

#pragma mark Dependencies

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark Initialization

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

    // renamed `hasEverHadMessage` -> `shouldBeVisible`
    if (!_shouldBeVisible) {
        NSNumber *_Nullable legacy_hasEverHadMessage = [coder decodeObjectForKey:@"hasEverHadMessage"];

        if (legacy_hasEverHadMessage != nil) {
            _shouldBeVisible = legacy_hasEverHadMessage.boolValue;
        }
    }

    NSDate *_Nullable lastMessageDate = [coder decodeObjectOfClass:NSDate.class forKey:@"lastMessageDate"];
    NSDate *_Nullable archivalDate = [coder decodeObjectOfClass:NSDate.class forKey:@"archivalDate"];

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
    __block BOOL didDetectCorruption = NO;
    [interactionsByThread enumerateKeysInGroup:self.uniqueId
                                    usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
                                        if (![key isKindOfClass:[NSString class]] || key.length < 1) {
                                            didDetectCorruption = YES;
                                            return;
                                        }
                                        [interactionIds addObject:key];
                                    }];

    if (didDetectCorruption) {
        [OWSPrimaryStorage incrementVersionOfDatabaseExtension:TSMessageDatabaseViewExtensionName];
    }

    for (NSString *interactionId in interactionIds) {
        // We need to fetch each interaction, since [TSInteraction removeWithTransaction:] does important work.
        TSInteraction *_Nullable interaction =
            [TSInteraction fetchObjectWithUniqueID:interactionId transaction:transaction];
        if (!interaction) {
            continue;
        }
        [interaction removeWithTransaction:transaction];
    }
}

- (BOOL)isNoteToSelf
{
    if (!IsNoteToSelfEnabled()) { return NO; }
    if (![self isKindOfClass:TSContactThread.class]) { return NO; }
    return [self.contactSessionID isEqual:[SNGeneralUtilities getUserPublicKey]];
}

#pragma mark To be subclassed.

- (BOOL)isGroupThread {
    return NO;
}

// Override in ContactThread
- (nullable NSString *)contactSessionID
{
    return nil;
}

- (NSString *)name {
    return nil;
}

- (NSString *)nameWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return nil;
}

- (NSArray<NSString *> *)recipientIdentifiers
{
    return @[];
}

#pragma mark Interactions

/**
 * Iterate over this thread's interactions
 */
- (void)enumerateInteractionsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                  usingBlock:(void (^)(TSInteraction *interaction, BOOL *stop))block
{
    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    [interactionsByThread
        enumerateKeysAndObjectsInGroup:self.uniqueId
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                TSInteraction *interaction = object;
                                block(interaction, stop);
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
                                            TSInteraction *interaction, BOOL *stop) {

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

- (BOOL)hasUnreadMentionMessageWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    __block BOOL hasUnreadMention = false;
    
    YapDatabaseViewTransaction *unreadMessages = [transaction ext:TSUnreadDatabaseViewExtensionName];
    [unreadMessages enumerateKeysAndObjectsInGroup:self.uniqueId
                                        usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
        if (![object isKindOfClass:[TSIncomingMessage class]]) {
            return;
        }
        TSIncomingMessage* unreadMessage = (TSIncomingMessage*)object;
        if (unreadMessage.read) {
            NSLog(@"Found an already read message in the * unread * messages list.");
            return;
        }
        
        if (unreadMessage.isUserMentioned) {
            hasUnreadMention = true;
            *stop = YES;
        }
    }];

    return hasUnreadMention;
    
}

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    for (id<OWSReadTracking> message in [self unseenMessagesWithTransaction:transaction]) {
        [message markAsReadAtTimestamp:[NSDate ows_millisecondTimeStamp] sendReadReceipt:YES transaction:transaction];
    }
}

- (nullable TSInteraction *)lastInteractionForInboxWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    __block NSUInteger missedCount = 0;
    __block TSInteraction *last = nil;
    [[transaction ext:TSMessageDatabaseViewExtensionName]
        enumerateKeysAndObjectsInGroup:self.uniqueId
                           withOptions:NSEnumerationReverse
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                missedCount++;
                                TSInteraction *interaction = (TSInteraction *)object;

                                if ([TSThread shouldInteractionAppearInInbox:interaction]) {
                                    last = interaction;

                                    // For long ignored threads, with lots of SN changes this can get really slow.
                                    // I see this in development because I have a lot of long forgotten threads with
                                    // members who's test devices are constantly reinstalled. We could add a
                                    // purpose-built DB view, but I think in the real world this is rare to be a
                                    // hotspot.

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
    if (interaction.isDynamicInteraction) {
        return NO;
    }
    
    if ([interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage *)interaction;
        if (message.isDeleted) {
            return NO;
        }
    }

    return YES;
}

- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(YapDatabaseReadWriteTransaction *)transaction {
    if (![self.class shouldInteractionAppearInInbox:lastMessage]) {
        return;
    }
    
    if ([_lastInteractionDate compare: lastMessage.receivedAtDate] == NSOrderedAscending) {
        _lastInteractionDate = lastMessage.receivedAtDate;
        [super saveWithTransaction:transaction];
    }

    if (!self.shouldBeVisible) {
        self.shouldBeVisible = YES;
        [self saveWithTransaction:transaction];
    } else {
        [self touchWithTransaction:transaction];
    }
}

#pragma mark Disappearing Messages

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

#pragma mark Drafts

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

#pragma mark Muting

- (BOOL)isMuted
{
    NSDate *mutedUntilDate = self.mutedUntilDate;
    NSDate *now = [NSDate date];
    return (mutedUntilDate != nil && [mutedUntilDate timeIntervalSinceDate:now] > 0);
}

- (void)updateWithMutedUntilDate:(NSDate * _Nullable)mutedUntilDate transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSThread *thread) {
                                 [thread setMutedUntilDate:mutedUntilDate];
                             }];

    [transaction addCompletionQueue:dispatch_get_main_queue() completionBlock:^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.muteSettingUpdated object:self.uniqueId];
    }];
}

@end

NS_ASSUME_NONNULL_END
