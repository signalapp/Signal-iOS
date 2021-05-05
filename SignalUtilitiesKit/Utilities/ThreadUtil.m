//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSQuotedReplyModel.h"
#import "OWSUnreadIndicator.h"
#import <SignalUtilitiesKit/OWSProfileManager.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SessionMessagingKit/OWSBlockingManager.h>
#import <SessionMessagingKit/OWSDisappearingMessagesConfiguration.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionMessagingKit/TSContactThread.h>
#import <SessionMessagingKit/TSDatabaseView.h>
#import <SessionMessagingKit/TSIncomingMessage.h>
#import <SessionMessagingKit/TSOutgoingMessage.h>
#import <SessionMessagingKit/TSThread.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>


NS_ASSUME_NONNULL_BEGIN

@interface ThreadDynamicInteractions ()

@property (nonatomic, nullable) NSNumber *focusMessagePosition;

@property (nonatomic, nullable) OWSUnreadIndicator *unreadIndicator;

@end

#pragma mark -

@implementation ThreadDynamicInteractions

- (void)clearUnreadIndicatorState
{
    self.unreadIndicator = nil;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[ThreadDynamicInteractions class]]) {
        return NO;
    }

    ThreadDynamicInteractions *other = (ThreadDynamicInteractions *)object;
    return ([NSObject isNullableObject:self.focusMessagePosition equalTo:other.focusMessagePosition] &&
        [NSObject isNullableObject:self.unreadIndicator equalTo:other.unreadIndicator]);
}

@end

@implementation ThreadUtil

#pragma mark - Dependencies

+ (YapDatabaseConnection *)dbConnection
{
    return SSKEnvironment.shared.primaryStorage.dbReadWriteConnection;
}

#pragma mark - Dynamic Interactions

+ (ThreadDynamicInteractions *)ensureDynamicInteractionsForThread:(TSThread *)thread
                                                  blockingManager:(OWSBlockingManager *)blockingManager
                                                     dbConnection:(YapDatabaseConnection *)dbConnection
                                      hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                                              lastUnreadIndicator:(nullable OWSUnreadIndicator *)lastUnreadIndicator
                                                   focusMessageId:(nullable NSString *)focusMessageId
                                                     maxRangeSize:(int)maxRangeSize
{
    OWSAssertDebug(thread);
    OWSAssertDebug(dbConnection);
    OWSAssertDebug(blockingManager);
    OWSAssertDebug(maxRangeSize > 0);

    ThreadDynamicInteractions *result = [ThreadDynamicInteractions new];

    [dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        // Determine if there are "unread" messages in this conversation.
        // If we've been passed a firstUnseenInteractionTimestampParameter,
        // just use that value in order to preserve continuity of the
        // unread messages indicator after all messages in the conversation
        // have been marked as read.
        //
        // IFF this variable is non-null, there are unseen messages in the thread.
        NSNumber *_Nullable firstUnseenSortId = nil;
        if (lastUnreadIndicator) {
            firstUnseenSortId = @(lastUnreadIndicator.firstUnseenSortId);
        } else {
            TSInteraction *_Nullable firstUnseenInteraction =
                [[TSDatabaseView unseenDatabaseViewExtension:transaction] firstObjectInGroup:thread.uniqueId];
            if (firstUnseenInteraction && firstUnseenInteraction.sortId != NULL) {
                firstUnseenSortId = @(firstUnseenInteraction.sortId);
            }
        }

        [self ensureUnreadIndicator:result
                                    thread:thread
                               transaction:transaction
                              maxRangeSize:maxRangeSize
            nonBlockingSafetyNumberChanges:@[]
               hideUnreadMessagesIndicator:hideUnreadMessagesIndicator
                         firstUnseenSortId:firstUnseenSortId];

        // Determine the position of the focus message _after_ performing any mutations
        // around dynamic interactions.
        if (focusMessageId != nil) {
            result.focusMessagePosition =
                [self focusMessagePositionForThread:thread transaction:transaction focusMessageId:focusMessageId];
        }
    }];

    return result;
}

+ (void)ensureUnreadIndicator:(ThreadDynamicInteractions *)dynamicInteractions
                            thread:(TSThread *)thread
                       transaction:(YapDatabaseReadTransaction *)transaction
                      maxRangeSize:(int)maxRangeSize
    nonBlockingSafetyNumberChanges:(NSArray<TSInteraction *> *)nonBlockingSafetyNumberChanges
       hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                 firstUnseenSortId:(nullable NSNumber *)firstUnseenSortId
{
    OWSAssertDebug(dynamicInteractions);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(nonBlockingSafetyNumberChanges);

    if (hideUnreadMessagesIndicator) {
        return;
    }
    if (!firstUnseenSortId) {
        // If there are no unseen interactions, don't show an unread indicator.
        return;
    }

    YapDatabaseViewTransaction *threadMessagesTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
    OWSAssertDebug([threadMessagesTransaction isKindOfClass:[YapDatabaseViewTransaction class]]);

    // Determine unread indicator position, if necessary.
    //
    // Enumerate in reverse to count the number of messages
    // after the unseen messages indicator.  Not all of
    // them are unnecessarily unread, but we need to tell
    // the messages view the position of the unread indicator,
    // so that it can widen its "load window" to always show
    // the unread indicator.
    __block long visibleUnseenMessageCount = 0;
    __block TSInteraction *interactionAfterUnreadIndicator = nil;
    __block BOOL hasMoreUnseenMessages = NO;
    [threadMessagesTransaction
        enumerateKeysAndObjectsInGroup:thread.uniqueId
                           withOptions:NSEnumerationReverse
                            usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                if (![object isKindOfClass:[TSInteraction class]]) {
                                    OWSFailDebug(@"Expected a TSInteraction: %@", [object class]);
                                    return;
                                }

                                TSInteraction *interaction = (TSInteraction *)object;

                                if (interaction.isDynamicInteraction) {
                                    // Ignore dynamic interactions, if any.
                                    return;
                                }

                                if (interaction.sortId < firstUnseenSortId.unsignedLongLongValue) {
                                    // By default we want the unread indicator to appear just before
                                    // the first unread message.
                                    *stop = YES;
                                    return;
                                }

                                visibleUnseenMessageCount++;

                                interactionAfterUnreadIndicator = interaction;
        
                                if (visibleUnseenMessageCount + 1 >= maxRangeSize) {
                                    // If there are more unseen messages than can be displayed in the
                                    // messages view, show the unread indicator at the top of the
                                    // displayed messages.
                                    *stop = YES;
                                    hasMoreUnseenMessages = YES;
                                }
                            }];

    if (!interactionAfterUnreadIndicator) {
        // If we can't find an interaction after the unread indicator,
        // don't show it.  All unread messages may have been deleted or
        // expired.
        return;
    }
    OWSAssertDebug(visibleUnseenMessageCount > 0);

    NSInteger unreadIndicatorPosition = visibleUnseenMessageCount;

    dynamicInteractions.unreadIndicator =
        [[OWSUnreadIndicator alloc] initWithFirstUnseenSortId:firstUnseenSortId.unsignedLongLongValue
                                        hasMoreUnseenMessages:hasMoreUnseenMessages
                         missingUnseenSafetyNumberChangeCount:nonBlockingSafetyNumberChanges.count
                                      unreadIndicatorPosition:unreadIndicatorPosition];
    OWSLogInfo(@"Creating Unread Indicator: %llu", dynamicInteractions.unreadIndicator.firstUnseenSortId);
}

+ (nullable NSNumber *)focusMessagePositionForThread:(TSThread *)thread
                                         transaction:(YapDatabaseReadTransaction *)transaction
                                      focusMessageId:(NSString *)focusMessageId
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(focusMessageId);

    YapDatabaseViewTransaction *databaseView = [transaction ext:TSMessageDatabaseViewExtensionName];

    NSString *_Nullable group = nil;
    NSUInteger index;
    BOOL success =
        [databaseView getGroup:&group index:&index forKey:focusMessageId inCollection:TSInteraction.collection];
    if (!success) {
        // This might happen if the focus message has disappeared
        // before this view could appear.
        OWSFailDebug(@"failed to find focus message index.");
        return nil;
    }
    if (![group isEqualToString:thread.uniqueId]) {
        OWSFailDebug(@"focus message has invalid group.");
        return nil;
    }
    NSUInteger count = [databaseView numberOfItemsInGroup:thread.uniqueId];
    if (index >= count) {
        OWSFailDebug(@"focus message has invalid index.");
        return nil;
    }
    NSUInteger position = (count - index) - 1;
    return @(position);
}

#pragma mark - Delete Content

+ (void)deleteAllContent
{
    OWSLogInfo(@"");

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self removeAllObjectsInCollection:[TSThread collection]
                                     class:[TSThread class]
                               transaction:transaction];
        [self removeAllObjectsInCollection:[TSInteraction collection]
                                     class:[TSInteraction class]
                               transaction:transaction];
        [self removeAllObjectsInCollection:[TSAttachment collection]
                                     class:[TSAttachment class]
                               transaction:transaction];
        @try {
            [self removeAllObjectsInCollection:[SignalRecipient collection]
                                         class:[SignalRecipient class]
                                   transaction:transaction];
        } @catch (NSException *exception) {
            // Do nothing
        }
    }];
    [TSAttachmentStream deleteAttachments];
}

+ (void)removeAllObjectsInCollection:(NSString *)collection
                               class:(Class) class
                         transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssertDebug(collection.length > 0);
    OWSAssertDebug(class);
    OWSAssertDebug(transaction);

    NSArray<NSString *> *_Nullable uniqueIds = [transaction allKeysInCollection:collection];
    if (!uniqueIds) {
        OWSFailDebug(@"couldn't load uniqueIds for collection: %@.", collection);
        return;
    }
    OWSLogInfo(@"Deleting %lu objects from: %@", (unsigned long)uniqueIds.count, collection);
    NSUInteger count = 0;
    for (NSString *uniqueId in uniqueIds) {
        // We need to fetch each object, since [TSYapDatabaseObject removeWithTransaction:] sometimes does important
        // work.
        TSYapDatabaseObject *_Nullable object = [class fetchObjectWithUniqueID:uniqueId transaction:transaction];
        if (!object) {
            OWSFailDebug(@"couldn't load object for deletion: %@.", collection);
            continue;
        }
        [object removeWithTransaction:transaction];
        count++;
    };
    OWSLogInfo(@"Deleted %lu/%lu objects from: %@", (unsigned long)count, (unsigned long)uniqueIds.count, collection);
}

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                      authorId:(NSString *)authorId
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorId.length > 0);

    NSString *localNumber = [TSAccountManager localNumber];
    if (localNumber.length < 1) {
        OWSFailDebug(@"missing long number.");
        return nil;
    }

    NSArray<TSInteraction *> *interactions =
        [TSInteraction interactionsWithTimestamp:timestamp
                                          filter:^(TSInteraction *interaction) {
                                              NSString *_Nullable messageAuthorId = nil;
                                              if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
                                                  TSIncomingMessage *incomingMessage = (TSIncomingMessage *)interaction;
                                                  messageAuthorId = incomingMessage.authorId;
                                              } else if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
                                                  messageAuthorId = localNumber;
                                              }
                                              if (messageAuthorId.length < 1) {
                                                  return NO;
                                              }

                                              if (![authorId isEqualToString:messageAuthorId]) {
                                                  return NO;
                                              }
                                              if (![interaction.uniqueThreadId isEqualToString:threadUniqueId]) {
                                                  return NO;
                                              }
                                              return YES;
                                          }
                                 withTransaction:transaction];
    if (interactions.count < 1) {
        return nil;
    }
    if (interactions.count > 1) {
        // In case of collision, take the first.
        OWSLogError(@"more than one matching interaction in thread.");
    }
    return interactions.firstObject;
}

@end

NS_ASSUME_NONNULL_END
