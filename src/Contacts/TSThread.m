//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "OWSReadTracking.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSThread ()

@property (nonatomic) NSDate *creationDate;
@property (nonatomic, copy) NSDate *archivalDate;
@property (nonatomic) NSDate *lastMessageDate;
@property (nonatomic, copy) NSString *messageDraft;
@property (atomic, nullable) NSDate *mutedUntilDate;

- (TSInteraction *)lastInteraction;

@end

@implementation TSThread

+ (NSString *)collection {
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId {
    self = [super initWithUniqueId:uniqueId];

    if (self) {
        _archivalDate    = nil;
        _lastMessageDate = nil;
        _creationDate    = [NSDate date];
        _messageDraft    = nil;
    }

    return self;
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];

    __block NSMutableArray<NSString *> *interactionIds = [[NSMutableArray alloc] init];
    [self enumerateInteractionsWithTransaction:transaction
                                    usingBlock:^(TSInteraction *interaction, YapDatabaseReadTransaction *transaction) {
                                        [interactionIds addObject:interaction.uniqueId];
                                    }];

    for (NSString *interactionId in interactionIds) {
        // This might seem redundant since we're fetching the interaction twice, once above to get the uniqueIds
        // and then again here. The issue is we can't remove them within the enumeration (you can't mutate an
        // enumeration source), but we also want to avoid instantiating an entire threads worth of Interaction objects
        // at once. This way we only have a threads worth of interactionId's.
        TSInteraction *interaction = [TSInteraction fetchObjectWithUniqueID:interactionId transaction:transaction];
        [interaction removeWithTransaction:transaction];
    }
}

#pragma mark To be subclassed.

- (BOOL)isGroupThread {
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

// Override in ContactThread
- (nullable NSString *)contactIdentifier
{
    return nil;
}

- (NSString *)name {
    NSAssert(FALSE, @"Should be implemented in subclasses");
    return nil;
}

- (nullable UIImage *)image
{
    return nil;
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
    void (^interactionBlock)(NSString *, NSString *, id, id, NSUInteger, BOOL *) = ^void(NSString *_Nonnull collection,
        NSString *_Nonnull key,
        id _Nonnull object,
        id _Nonnull metadata,
        NSUInteger index,
        BOOL *_Nonnull stop) {

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
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
    [self enumerateInteractionsUsingBlock:^(TSInteraction *_Nonnull interaction) {
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
    [[self dbConnection] readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
        count = [interactionsByThread numberOfItemsInGroup:self.uniqueId];
    }];
    return count;
}

- (BOOL)hasUnreadMessages {
    TSInteraction *interaction = self.lastInteraction;
    BOOL hasUnread = NO;

    if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
        hasUnread = ![(TSIncomingMessage *)interaction wasRead];
    }

    return hasUnread;
}

- (NSArray<id<OWSReadTracking> > *)unreadMessagesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<id<OWSReadTracking> > *messages = [NSMutableArray new];
    [[transaction ext:TSUnreadDatabaseViewExtensionName]
        enumerateRowsInGroup:self.uniqueId
                  usingBlock:^(
                      NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                      if (![object conformsToProtocol:@protocol(OWSReadTracking)]) {
                          DDLogError(@"%@ Unexpected object in unread messages: %@", self.tag, object);
                      }
                      [messages addObject:(id<OWSReadTracking>)object];
                  }];

    return [messages copy];
}

- (NSArray<id<OWSReadTracking> > *)unreadMessages
{
    __block NSArray<id<OWSReadTracking> > *messages;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        messages = [self unreadMessagesWithTransaction:transaction];
    }];

    return messages;
}

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    for (id<OWSReadTracking> message in [self unreadMessagesWithTransaction:transaction]) {
        [message markAsReadLocallyWithTransaction:transaction];
    }
}

- (void)markAllAsRead
{
    for (id<OWSReadTracking> message in [self unreadMessages]) {
        [message markAsReadLocally];
    }
}

- (TSInteraction *) lastInteraction {
    __block TSInteraction *last;
    [TSStorageManager.sharedManager.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
        last = [[transaction ext:TSMessageDatabaseViewExtensionName] lastObjectInGroup:self.uniqueId];
    }];
    return (TSInteraction *)last;
}

- (NSDate *)lastMessageDate {
    if (_lastMessageDate) {
        return _lastMessageDate;
    } else {
        return _creationDate;
    }
}

- (NSString *)lastMessageLabel {
    if (self.lastInteraction == nil) {
        return @"";
    } else {
        return [self lastInteraction].description;
    }
}

- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSDate *lastMessageDate = [lastMessage receiptDateForSorting];

    if (!_lastMessageDate || [lastMessageDate timeIntervalSinceDate:self.lastMessageDate] > 0) {
        _lastMessageDate = lastMessageDate;

        [self saveWithTransaction:transaction];
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

// This method does the work for the "updateWith..." methods.  Please see
// the header for a discussion of those methods.
- (void)applyChangeToSelfAndLatestThread:(YapDatabaseReadWriteTransaction *)transaction
                             changeBlock:(void (^)(TSThread *))changeBlock
{
    OWSAssert(transaction);
    
    changeBlock(self);
    
    NSString *collection = [[self class] collection];
    TSThread *latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
    if (latestInstance) {
        changeBlock(latestInstance);
        [latestInstance saveWithTransaction:transaction];
    } else {
        // This message has not yet been saved.
        [self saveWithTransaction:transaction];
    }
}

- (void)updateWithMutedUntilDate:(NSDate *)mutedUntilDate
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestThread:transaction
                                            changeBlock:^(TSThread *thread) {
                                                [thread setMutedUntilDate:mutedUntilDate];
                                            }];
    }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
