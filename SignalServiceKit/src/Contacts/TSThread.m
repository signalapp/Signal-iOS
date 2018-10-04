//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "Cryptography.h"
#import "NSDate+OWS.h"
#import "NSString+SSK.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadTracking.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInteraction.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSOutgoingMessage.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSThread ()

@property (nonatomic) NSDate *creationDate;
@property (nonatomic, copy, nullable) NSDate *archivalDate;
@property (nonatomic) NSString *conversationColorName;
@property (nonatomic, nullable) NSDate *lastMessageDate;

@property (nonatomic, copy, nullable) NSString *messageDraft;
@property (atomic, nullable) NSDate *mutedUntilDate;

@end

#pragma mark -

@implementation TSThread

+ (NSString *)collection {
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId
{
    self = [super initWithUniqueId:uniqueId];

    if (self) {
        _archivalDate    = nil;
        _lastMessageDate = nil;
        _creationDate    = [NSDate date];
        _messageDraft    = nil;

        NSString *_Nullable contactId = self.contactIdentifier;
        if (contactId.length > 0) {
            // To be consistent with colors synced to desktop
            _conversationColorName = [self.class stableColorNameForNewConversationWithString:contactId];
        } else {
            _conversationColorName = [self.class stableColorNameForNewConversationWithString:self.uniqueId];
        }
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    
    if (_conversationColorName.length == 0) {
        NSString *_Nullable contactId = self.contactIdentifier;
        if (contactId.length > 0) {
            // To be consistent with colors synced to desktop
            _conversationColorName = [self.class stableColorNameForLegacyConversationWithString:contactId];
        } else {
            _conversationColorName = [self.class stableColorNameForLegacyConversationWithString:self.uniqueId];
        }
    }
    
    return self;
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

#pragma mark To be subclassed.

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

- (BOOL)hasSafetyNumbers
{
    return NO;
}

#pragma mark Interactions

/**
 * Iterate over this thread's interactions
 */
- (void)enumerateInteractionsWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
                                  usingBlock:(void (^)(TSInteraction *interaction,
                                                 YapDatabaseReadTransaction *transaction))block
{
    void (^interactionBlock)(NSString *, NSString *, id, id, NSUInteger, BOOL *) = ^void(
        NSString *collection, NSString *key, id _Nonnull object, id _Nonnull metadata, NSUInteger index, BOOL *stop) {
        TSInteraction *interaction = object;
        block(interaction, transaction);
    };

    YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
    [interactionsByThread enumerateRowsInGroup:self.uniqueId usingBlock:interactionBlock];
}

/**
 * Enumerates all the threads interactions. Note this will explode if you try to create a transaction in the block.
 * If you need a transaction, use the sister method: `enumerateInteractionsWithTransaction:usingBlock`
 */
- (void)enumerateInteractionsUsingBlock:(void (^)(TSInteraction *interaction))block
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self enumerateInteractionsWithTransaction:transaction
                                        usingBlock:^(
                                            TSInteraction *interaction, YapDatabaseReadTransaction *transaction) {

                                            block(interaction);
                                        }];
    }];
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

- (NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *)receivedMessagesForInvalidKey:(NSData *)key
{
    NSMutableArray *errorMessages = [NSMutableArray new];
    [self enumerateInteractionsUsingBlock:^(TSInteraction *interaction) {
        if ([interaction isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
            TSInvalidIdentityKeyReceivingErrorMessage *error = (TSInvalidIdentityKeyReceivingErrorMessage *)interaction;
            if ([[error newIdentityKey] isEqualToData:key]) {
                [errorMessages addObject:(TSInvalidIdentityKeyReceivingErrorMessage *)interaction];
            }
        }
    }];

    return [errorMessages copy];
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
        enumerateRowsInGroup:self.uniqueId
                  usingBlock:^(
                      NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                      if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                          OWSFailDebug(@"Unexpected object in unseen messages: %@", [object class]);
                          return;
                      }
                      [messages addObject:(id<OWSReadTracking>)object];
                  }];

    return [messages copy];
}

- (NSUInteger)unreadMessageCountWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:self.uniqueId];
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
     enumerateRowsInGroup:self.uniqueId
     withOptions:NSEnumerationReverse
     usingBlock:^(
                  NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {
         
         OWSAssertDebug([object isKindOfClass:[TSInteraction class]]);

         missedCount++;
         TSInteraction *interaction = (TSInteraction *)object;
         
         if ([TSThread shouldInteractionAppearInInbox:interaction]) {
             last = interaction;

             // For long ignored threads, with lots of SN changes this can get really slow.
             // I see this in development because I have a lot of long forgotten threads with members
             // who's test devices are constantly reinstalled. We could add a purpose-built DB view,
             // but I think in the real world this is rare to be a hotspot.
             if (missedCount > 50) {
                 OWSLogWarn(@"found last interaction for inbox after skipping %lu items", (unsigned long)missedCount);
             }
             *stop = YES;
         }
     }];
    return last;
}

- (NSDate *)lastMessageDate {
    if (_lastMessageDate) {
        return _lastMessageDate;
    } else {
        return _creationDate;
    }
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
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        TSInfoMessage *infoMessage = (TSInfoMessage *)interaction;
        if (infoMessage.messageType == TSInfoMessageVerificationStateChange) {
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

    self.hasEverHadMessage = YES;

    NSDate *lastMessageDate = [lastMessage dateForSorting];
    if (!_lastMessageDate || [lastMessageDate timeIntervalSinceDate:self.lastMessageDate] > 0) {
        _lastMessageDate = lastMessageDate;

        [self saveWithTransaction:transaction];
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

#pragma mark Archival

- (nullable NSDate *)archivalDate
{
    return _archivalDate;
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    [self archiveThreadWithTransaction:transaction referenceDate:[NSDate date]];
}

- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction referenceDate:(NSDate *)date {
    [self markAllAsReadWithTransaction:transaction];
    _archivalDate = date;

    [self saveWithTransaction:transaction];
}

- (void)unarchiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction {
    _archivalDate = nil;
    [self saveWithTransaction:transaction];
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

#pragma mark - Conversation Color

+ (NSArray<NSString *> *)colorNamesForNewConversation
{
    // all conversation colors except "steel"
    return @[
        @"crimson",
        @"vermilion",
        @"burlap",
        @"forest",
        @"wintergreen",
        @"teal",
        @"blue",
        @"indigo",
        @"violet",
        @"plum",
        @"taupe"
    ];
}

+ (NSString *)stableConversationColorNameForString:(NSString *)colorSeed colorNames:(NSArray<NSString *> *)colorNames
{
    NSData *contactData = [colorSeed dataUsingEncoding:NSUTF8StringEncoding];

    unsigned long long hash = 0;
    NSUInteger hashingLength = sizeof(hash);
    NSData *_Nullable hashData = [Cryptography computeSHA256Digest:contactData truncatedToBytes:hashingLength];
    if (hashData) {
        [hashData getBytes:&hash length:hashingLength];
    } else {
        OWSFailDebug(@"could not compute hash for color seed.");
    }

    NSUInteger index = (hash % colorNames.count);
    return [colorNames objectAtIndex:index];
}

+ (NSString *)stableColorNameForNewConversationWithString:(NSString *)colorSeed
{
    return [self stableConversationColorNameForString:colorSeed colorNames:self.colorNamesForNewConversation];
}

// After introducing new conversation colors, we want to try to maintain as close
// as possible to the old color for an existing thread.
+ (NSString *)stableColorNameForLegacyConversationWithString:(NSString *)colorSeed
{
    return [self stableConversationColorNameForString:colorSeed colorNames:self.legacyConversationColorNames];
}

+ (NSArray<NSString *> *)legacyConversationColorNames
{
    return @[
             @"red",
             @"pink",
             @"purple",
             @"indigo",
             @"blue",
             @"cyan",
             @"teal",
             @"green",
             @"deep_orange",
             @"grey"
    ];
}

- (void)updateConversationColorName:(NSString *)colorName transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSThread *thread) {
                                 thread.conversationColorName = colorName;
                             }];
}

@end

NS_ASSUME_NONNULL_END
