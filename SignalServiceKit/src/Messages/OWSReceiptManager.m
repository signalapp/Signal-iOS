//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSReceiptManager.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSOutgoingReceiptManager.h>
#import <SignalServiceKit/OWSReadReceiptsForLinkedDevicesMessage.h>
#import <SignalServiceKit/OWSReceiptsForSenderMessage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

NSString *const OWSReceiptManagerCollection = @"OWSReadReceiptManagerCollection";
NSString *const OWSReceiptManagerAreReadReceiptsEnabled = @"areReadReceiptsEnabled";

@interface OWSReceiptManager ()

// Should only be accessed while synchronized on the OWSReceiptManager.
@property (nonatomic) BOOL isProcessing;

@property (atomic, nullable) NSNumber *areReadReceiptsEnabledCached;

@end

#pragma mark -

@implementation OWSReceiptManager

+ (SDSKeyValueStore *)keyValueStore
{
    static SDSKeyValueStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(
        &onceToken, ^{ instance = [[SDSKeyValueStore alloc] initWithCollection:OWSReceiptManagerCollection]; });
    return instance;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    // Start processing.
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self scheduleProcessing]; });

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Schedules a processing pass, unless one is already scheduled.
- (void)scheduleProcessing
{
    OWSAssertDebug(AppReadiness.isAppReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self) {
            if (self.isProcessing) {
                return;
            }

            self.isProcessing = YES;
        }

        [self processReceiptsForLinkedDevicesWithCompletion:^{
            @synchronized(self) {
                OWSAssertDebug(self.isProcessing);

                self.isProcessing = NO;
            }
        }];
    });
}

#pragma mark - Mark as Read Locally

- (void)markAsReadLocallyBeforeSortId:(uint64_t)sortId
                               thread:(TSThread *)thread
             hasPendingMessageRequest:(BOOL)hasPendingMessageRequest
                           completion:(void (^)(void))completion
{
    OWSAssertDebug(thread);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];

        uint64_t readTimestamp = [NSDate ows_millisecondTimeStamp];
        __block NSArray<id<OWSReadTracking>> *unreadMessages;
        __block NSArray<TSOutgoingMessage *> *messagesWithUnreadReactions;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            unreadMessages = [interactionFinder unreadMessagesBeforeSortId:sortId
                                                               transaction:transaction.unwrapGrdbRead];

            messagesWithUnreadReactions =
                [interactionFinder messagesWithUnreadReactionsBeforeSortId:sortId
                                                               transaction:transaction.unwrapGrdbRead];
        }];

        if (unreadMessages.count < 1 && messagesWithUnreadReactions.count < 1) {
            // Avoid unnecessary writes.
            dispatch_async(dispatch_get_main_queue(), completion);
            return;
        }

        // Mark as read in batches.
        NSComparisonResult (^interactionComparator)(id, id) = ^NSComparisonResult(id left, id right) {
            if (![left isKindOfClass:[TSInteraction class]] || ![right isKindOfClass:[TSInteraction class]]) {
                OWSFailDebug(@"Unexpected object: %@ %@", [left class], [right class]);
                return NSOrderedSame;
            }
            TSInteraction *leftInteraction = left;
            TSInteraction *rightInteraction = right;
            if (leftInteraction.sortId == rightInteraction.sortId) {
                return NSOrderedSame;
            } else if (leftInteraction.sortId < rightInteraction.sortId) {
                return NSOrderedAscending;
            } else {
                return NSOrderedDescending;
            }
        };
        unreadMessages = [unreadMessages sortedArrayUsingComparator:interactionComparator];
        messagesWithUnreadReactions = [messagesWithUnreadReactions sortedArrayUsingComparator:interactionComparator];

        const NSUInteger maxBatchSize = 500;
        while (unreadMessages.count > 0) {
            NSUInteger batchSize = MIN(unreadMessages.count, maxBatchSize);
            NSArray<id<OWSReadTracking>> *batch = [unreadMessages subarrayWithRange:NSMakeRange(0, batchSize)];
            unreadMessages =
                [unreadMessages subarrayWithRange:NSMakeRange(batchSize, unreadMessages.count - batchSize)];
            OWSAssertDebug(batch.count > 0);
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                OWSReceiptCircumstance circumstance = hasPendingMessageRequest
                    ? OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest
                    : OWSReceiptCircumstanceOnThisDevice;
                [self markMessagesAsRead:batch
                                  thread:thread
                           readTimestamp:readTimestamp
                            circumstance:circumstance
                             transaction:transaction];
            });
        }
        while (messagesWithUnreadReactions.count > 0) {
            NSUInteger batchSize = MIN(messagesWithUnreadReactions.count, maxBatchSize);
            NSArray<TSOutgoingMessage *> *batch =
                [messagesWithUnreadReactions subarrayWithRange:NSMakeRange(0, batchSize)];
            messagesWithUnreadReactions = [messagesWithUnreadReactions
                subarrayWithRange:NSMakeRange(batchSize, messagesWithUnreadReactions.count - batchSize)];
            OWSAssertDebug(batch.count > 0);
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                for (TSOutgoingMessage *message in batch) {
                    [message markUnreadReactionsAsReadWithTransaction:transaction];
                }

                [self sendLinkedDeviceReadReceiptForMessages:batch thread:thread transaction:transaction];
            });
        }
        dispatch_async(dispatch_get_main_queue(), completion);
    });
}

- (void)messageWasRead:(TSIncomingMessage *)message
                thread:(TSThread *)thread
          circumstance:(OWSReceiptCircumstance)circumstance
           transaction:(SDSAnyWriteTransaction *)transaction
{
    switch (circumstance) {
        case OWSReceiptCircumstanceOnLinkedDevice:
            // nothing further to do
            return;
        case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReceiptRecorder recordPendingReadReceiptForMessage:message
                                                                         thread:thread
                                                                    transaction:transaction.unwrapGrdbWrite];
            }
            break;
        case OWSReceiptCircumstanceOnThisDevice: {
            [self enqueueLinkedDeviceReadReceiptForMessage:message transaction:transaction];
            [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];

            if (message.authorAddress.isLocalAddress) {
                OWSFailDebug(@"We don't support incoming messages from self.");
                return;
            }

            if ([self areReadReceiptsEnabled]) {
                OWSLogVerbose(@"Enqueuing read receipt for sender.");
                [self.outgoingReceiptManager enqueueReadReceiptForAddress:message.authorAddress
                                                                timestamp:message.timestamp
                                                              transaction:transaction];
            }
            break;
        }
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            [self enqueueLinkedDeviceReadReceiptForMessage:message transaction:transaction];
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReceiptRecorder recordPendingReadReceiptForMessage:message
                                                                         thread:thread
                                                                    transaction:transaction.unwrapGrdbWrite];
            }
            break;
    }
}

- (void)messageWasViewed:(TSIncomingMessage *)message
                  thread:(TSThread *)thread
            circumstance:(OWSReceiptCircumstance)circumstance
             transaction:(SDSAnyWriteTransaction *)transaction
{
    switch (circumstance) {
        case OWSReceiptCircumstanceOnLinkedDevice:
            // nothing further to do
            return;
        case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReceiptRecorder recordPendingViewedReceiptForMessage:message
                                                                           thread:thread
                                                                      transaction:transaction.unwrapGrdbWrite];
            }
            break;
        case OWSReceiptCircumstanceOnThisDevice: {
            [self enqueueLinkedDeviceViewedReceiptForMessage:message transaction:transaction];
            [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];

            if (message.authorAddress.isLocalAddress) {
                OWSFailDebug(@"We don't support incoming messages from self.");
                return;
            }

            if ([self areReadReceiptsEnabled]) {
                OWSLogVerbose(@"Enqueuing viewed receipt for sender.");
                [self.outgoingReceiptManager enqueueViewedReceiptForAddress:message.authorAddress
                                                                  timestamp:message.timestamp
                                                                transaction:transaction];
            }
            break;
        }
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            [self enqueueLinkedDeviceViewedReceiptForMessage:message transaction:transaction];
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReceiptRecorder recordPendingViewedReceiptForMessage:message
                                                                           thread:thread
                                                                      transaction:transaction.unwrapGrdbWrite];
            }
            break;
    }
}

#pragma mark - Read Receipts From Recipient

- (NSArray<NSNumber *> *)processReadReceiptsFromRecipient:(SignalServiceAddress *)address
                                           sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                                            readTimestamp:(uint64_t)readTimestamp
                                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(sentTimestamps);

    NSMutableArray<NSNumber *> *sentTimestampsMissingMessage = [NSMutableArray new];

    if (![self areReadReceiptsEnabled]) {
        OWSLogInfo(@"Ignoring incoming receipt message as read receipts are disabled.");
        return @[];
    }

    for (NSNumber *nsSentTimestamp in sentTimestamps) {
        UInt64 sentTimestamp = [nsSentTimestamp unsignedLongLongValue];

        NSError *error;
        NSArray<TSOutgoingMessage *> *messages = (NSArray<TSOutgoingMessage *> *)[InteractionFinder
            interactionsWithTimestamp:sentTimestamp
                               filter:^(TSInteraction *interaction) {
                                   return [interaction isKindOfClass:[TSOutgoingMessage class]];
                               }
                          transaction:transaction
                                error:&error];
        if (error != nil) {
            OWSFailDebug(@"Error loading interactions: %@", error);
        }

        if (messages.count > 1) {
            OWSLogError(@"More than one matching message with timestamp: %llu.", sentTimestamp);
        }

        if (messages.count > 0) {
            // TODO: We might also need to "mark as read by recipient" any older messages
            // from us in that thread.  Or maybe this state should hang on the thread?
            for (TSOutgoingMessage *message in messages) {
                [message updateWithReadRecipient:address readTimestamp:readTimestamp transaction:transaction];
            }
        } else {
            [sentTimestampsMissingMessage addObject:@(sentTimestamp)];
        }
    }

    return [sentTimestampsMissingMessage copy];
}

- (NSArray<NSNumber *> *)processViewedReceiptsFromRecipient:(SignalServiceAddress *)address
                                             sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                                            viewedTimestamp:(uint64_t)viewedTimestamp
                                                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(sentTimestamps);

    NSMutableArray<NSNumber *> *sentTimestampsMissingMessage = [NSMutableArray new];

    if (![self areReadReceiptsEnabled]) {
        OWSLogInfo(@"Ignoring incoming receipt message as read receipts are disabled.");
        return @[];
    }

    for (NSNumber *nsSentTimestamp in sentTimestamps) {
        UInt64 sentTimestamp = [nsSentTimestamp unsignedLongLongValue];

        NSError *error;
        NSArray<TSOutgoingMessage *> *messages = (NSArray<TSOutgoingMessage *> *)[InteractionFinder
            interactionsWithTimestamp:sentTimestamp
                               filter:^(TSInteraction *interaction) {
                                   return [interaction isKindOfClass:[TSOutgoingMessage class]];
                               }
                          transaction:transaction
                                error:&error];
        if (error != nil) {
            OWSFailDebug(@"Error loading interactions: %@", error);
        }

        if (messages.count > 1) {
            OWSLogError(@"More than one matching message with timestamp: %llu.", sentTimestamp);
        }

        if (messages.count > 0) {
            for (TSOutgoingMessage *message in messages) {
                [message updateWithViewedRecipient:address viewedTimestamp:viewedTimestamp transaction:transaction];
            }
        } else {
            [sentTimestampsMissingMessage addObject:@(sentTimestamp)];
        }
    }

    return [sentTimestampsMissingMessage copy];
}

#pragma mark - Linked Device Read Receipts

- (NSArray<SSKProtoSyncMessageRead *> *)processReadReceiptsFromLinkedDevice:
                                            (NSArray<SSKProtoSyncMessageRead *> *)readReceiptProtos
                                                              readTimestamp:(uint64_t)readTimestamp
                                                                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(readReceiptProtos);
    OWSAssertDebug(transaction);

    NSMutableArray<SSKProtoSyncMessageRead *> *receiptsMissingMessage = [NSMutableArray new];

    for (SSKProtoSyncMessageRead *readReceiptProto in readReceiptProtos) {
        SignalServiceAddress *_Nullable senderAddress = readReceiptProto.senderAddress;
        uint64_t messageIdTimestamp = readReceiptProto.timestamp;

        OWSAssertDebug(senderAddress.isValid);

        if (messageIdTimestamp == 0) {
            OWSFailDebug(@"messageIdTimestamp was unexpectedly 0");
            continue;
        }
        if (![SDS fitsInInt64:messageIdTimestamp]) {
            OWSFailDebug(@"Invalid messageIdTimestamp.");
            continue;
        }

        NSError *error;
        NSArray<TSMessage *> *messages = (NSArray<TSMessage *> *)[InteractionFinder
            interactionsWithTimestamp:messageIdTimestamp
                               filter:^(
                                   TSInteraction *interaction) { return [interaction isKindOfClass:[TSMessage class]]; }
                          transaction:transaction
                                error:&error];
        if (error != nil) {
            OWSFailDebug(@"Error loading interactions: %@", error);
        }

        if (messages.count > 0) {
            for (TSMessage *message in messages) {
                TSThread *_Nullable thread = [message threadWithTransaction:transaction];
                if (thread == nil) {
                    OWSFailDebug(@"thread was unexpectedly nil");
                    continue;
                }
                NSTimeInterval secondsSinceRead = [NSDate new].timeIntervalSince1970 - readTimestamp / 1000;
                OWSAssertDebug([message isKindOfClass:[TSMessage class]]);
                OWSLogDebug(@"read on linked device %f seconds ago", secondsSinceRead);
                [self markAsReadOnLinkedDevice:message
                                        thread:thread
                                 readTimestamp:readTimestamp
                                   transaction:transaction];
            }
        } else {
            [receiptsMissingMessage addObject:readReceiptProto];
        }
    }

    return [receiptsMissingMessage copy];
}

- (void)markAsReadOnLinkedDevice:(TSMessage *)message
                          thread:(TSThread *)thread
                   readTimestamp:(uint64_t)readTimestamp
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(message);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    if ([message isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
        BOOL hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
        OWSReceiptCircumstance circumstance = hasPendingMessageRequest
            ? OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest
            : OWSReceiptCircumstanceOnLinkedDevice;

        // Always re-mark the message as read to ensure any earlier read time is applied to disappearing messages.
        [incomingMessage markAsReadAtTimestamp:readTimestamp
                                        thread:thread
                                  circumstance:circumstance
                                   transaction:transaction];

        // Also mark any unread messages appearing earlier in the thread as read as well.
        [self markAsReadBeforeSortId:incomingMessage.sortId
                              thread:thread
                       readTimestamp:readTimestamp
                        circumstance:circumstance
                         transaction:transaction];
    } else if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        // Outgoing messages are always "read", but if we get a receipt
        // from our linked device about one that indicates that any reactions
        // we received on this message should also be marked read.
        [message markUnreadReactionsAsReadWithTransaction:transaction];
    }
}

- (NSArray<SSKProtoSyncMessageViewed *> *)processViewedReceiptsFromLinkedDevice:
                                              (NSArray<SSKProtoSyncMessageViewed *> *)viewedReceiptProtos
                                                                viewedTimestamp:(uint64_t)viewedTimestamp
                                                                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(viewedReceiptProtos);
    OWSAssertDebug(transaction);

    NSMutableArray<SSKProtoSyncMessageViewed *> *receiptsMissingMessage = [NSMutableArray new];

    for (SSKProtoSyncMessageViewed *viewedReceiptProto in viewedReceiptProtos) {
        SignalServiceAddress *_Nullable senderAddress = viewedReceiptProto.senderAddress;
        uint64_t messageIdTimestamp = viewedReceiptProto.timestamp;

        OWSAssertDebug(senderAddress.isValid);

        if (messageIdTimestamp == 0) {
            OWSFailDebug(@"messageIdTimestamp was unexpectedly 0");
            continue;
        }
        if (![SDS fitsInInt64:messageIdTimestamp]) {
            OWSFailDebug(@"Invalid messageIdTimestamp.");
            continue;
        }

        NSError *error;
        NSArray<TSMessage *> *messages = (NSArray<TSMessage *> *)[InteractionFinder
            interactionsWithTimestamp:messageIdTimestamp
                               filter:^(
                                   TSInteraction *interaction) { return [interaction isKindOfClass:[TSMessage class]]; }
                          transaction:transaction
                                error:&error];
        if (error != nil) {
            OWSFailDebug(@"Error loading interactions: %@", error);
        }

        if (messages.count > 0) {
            for (TSMessage *message in messages) {
                TSThread *_Nullable thread = [message threadWithTransaction:transaction];
                if (thread == nil) {
                    OWSFailDebug(@"thread was unexpectedly nil");
                    continue;
                }
                NSTimeInterval secondsSinceViewed = [NSDate new].timeIntervalSince1970 - viewedTimestamp / 1000;
                OWSAssertDebug([message isKindOfClass:[TSMessage class]]);
                OWSLogDebug(@"viewed on linked device %f seconds ago", secondsSinceViewed);
                [self markAsViewedOnLinkedDevice:message
                                          thread:thread
                                 viewedTimestamp:viewedTimestamp
                                     transaction:transaction];
            }
        } else {
            [receiptsMissingMessage addObject:viewedReceiptProto];
        }
    }

    return [receiptsMissingMessage copy];
}

- (void)markAsViewedOnLinkedDevice:(TSMessage *)message
                            thread:(TSThread *)thread
                   viewedTimestamp:(uint64_t)viewedTimestamp
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(message);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    if ([message isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
        BOOL hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
        OWSReceiptCircumstance circumstance = hasPendingMessageRequest
            ? OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest
            : OWSReceiptCircumstanceOnLinkedDevice;

        [incomingMessage markAsViewedAtTimestamp:viewedTimestamp
                                          thread:thread
                                    circumstance:circumstance
                                     transaction:transaction];
    }
}

#pragma mark - Mark As Read

- (void)markAsReadBeforeSortId:(uint64_t)sortId
                        thread:(TSThread *)thread
                 readTimestamp:(uint64_t)readTimestamp
                  circumstance:(OWSReceiptCircumstance)circumstance
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(sortId > 0);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    NSArray<id<OWSReadTracking>> *unreadMessages =
        [interactionFinder unreadMessagesBeforeSortId:sortId transaction:transaction.unwrapGrdbRead];
    if (unreadMessages.count < 1) {
        // Avoid unnecessary writes.
        return;
    }
    [self markMessagesAsRead:unreadMessages
                      thread:thread
               readTimestamp:readTimestamp
                circumstance:circumstance
                 transaction:transaction];
}

- (void)markMessagesAsRead:(NSArray<id<OWSReadTracking>> *)unreadMessages
                    thread:(TSThread *)thread
             readTimestamp:(uint64_t)readTimestamp
              circumstance:(OWSReceiptCircumstance)circumstance
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(unreadMessages.count > 0);
    OWSAssertDebug(transaction);

    switch (circumstance) {
        case OWSReceiptCircumstanceOnLinkedDevice:
            OWSLogInfo(@"Marking %lu messages as read by linked device.", (unsigned long)unreadMessages.count);
            break;
        case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
            OWSLogInfo(@"Marking %lu messages as read by linked device while pending message request.",
                (unsigned long)unreadMessages.count);
        case OWSReceiptCircumstanceOnThisDevice:
            OWSLogInfo(@"Marking %lu messages as read locally.", (unsigned long)unreadMessages.count);
            break;
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            OWSLogInfo(@"Marking %lu messages as read locally while pending message request.",
                (unsigned long)unreadMessages.count);
            break;
    }
    for (id<OWSReadTracking> readItem in unreadMessages) {
        [readItem markAsReadAtTimestamp:readTimestamp thread:thread circumstance:circumstance transaction:transaction];
    }
}

#pragma mark - Settings

- (void)prepareCachedValues
{
    // Clear out so we re-initialize if we ever re-run the "on launch" logic,
    // such as after a completed database transfer.
    self.areReadReceiptsEnabledCached = nil;

    [self areReadReceiptsEnabled];
}

- (BOOL)areReadReceiptsEnabled
{
    // We don't need to worry about races around this cached value.
    if (self.areReadReceiptsEnabledCached == nil) {
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            self.areReadReceiptsEnabledCached =
                @([OWSReceiptManager.keyValueStore getBool:OWSReceiptManagerAreReadReceiptsEnabled
                                              defaultValue:NO
                                               transaction:transaction]);
        }];
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (void)setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:(BOOL)value
{
    OWSLogInfo(@"setAreReadReceiptsEnabled: %d.", value);

    DatabaseStorageWrite(self.databaseStorage,
        ^(SDSAnyWriteTransaction *transaction) { [self setAreReadReceiptsEnabled:value transaction:transaction]; });

    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
    [SSKEnvironment.shared.storageServiceManager recordPendingLocalAccountUpdates];
}


- (void)setAreReadReceiptsEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction
{
    [OWSReceiptManager.keyValueStore setBool:value key:OWSReceiptManagerAreReadReceiptsEnabled transaction:transaction];
    self.areReadReceiptsEnabledCached = @(value);
}

@end

NS_ASSUME_NONNULL_END
