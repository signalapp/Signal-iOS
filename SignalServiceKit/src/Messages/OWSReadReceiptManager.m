//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptManager.h"
#import "AppReadiness.h"
#import "MessageSender.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSReceiptsForSenderMessage.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kIncomingMessageMarkedAsReadNotification = @"kIncomingMessageMarkedAsReadNotification";

#pragma mark -

NSString *const OWSReadReceiptManagerCollection = @"OWSReadReceiptManagerCollection";
NSString *const OWSReadReceiptManagerAreReadReceiptsEnabled = @"areReadReceiptsEnabled";

@interface OWSReadReceiptManager ()

// Should only be accessed while synchronized on the OWSReadReceiptManager.
@property (nonatomic) BOOL isProcessing;

@property (atomic, nullable) NSNumber *areReadReceiptsEnabledCached;

@end

#pragma mark -

@implementation OWSReadReceiptManager

+ (SDSKeyValueStore *)keyValueStore
{
    static SDSKeyValueStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SDSKeyValueStore alloc] initWithCollection:OWSReadReceiptManagerCollection];
    });
    return instance;
}

+ (instancetype)shared
{
    OWSAssert(SSKEnvironment.shared.readReceiptManager);

    return SSKEnvironment.shared.readReceiptManager;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    // Start processing.
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self scheduleProcessing];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSOutgoingReceiptManager *)outgoingReceiptManager
{
    OWSAssertDebug(SSKEnvironment.shared.outgoingReceiptManager);

    return SSKEnvironment.shared.outgoingReceiptManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<PendingReadReceiptRecorder>)pendingReadReceiptRecorder
{
    return SSKEnvironment.shared.pendingReadReceiptRecorder;
}

#pragma mark -

// Schedules a processing pass, unless one is already scheduled.
- (void)scheduleProcessing
{
    OWSAssertDebug(AppReadiness.isAppReady);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            if (self.isProcessing) {
                return;
            }
            
            self.isProcessing = YES;
        }
        
        [self processReadReceiptsForLinkedDevicesWithCompletion:^{
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
                OWSReadCircumstance circumstance = hasPendingMessageRequest
                    ? OWSReadCircumstanceReadOnThisDeviceWhilePendingMessageRequest
                    : OWSReadCircumstanceReadOnThisDevice;
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
          circumstance:(OWSReadCircumstance)circumstance
           transaction:(SDSAnyWriteTransaction *)transaction;
{
    switch (circumstance) {
        case OWSReadCircumstanceReadOnLinkedDevice:
            // nothing further to do
            return;
        case OWSReadCircumstanceReadOnLinkedDeviceWhilePendingMessageRequest:
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReadReceiptRecorder recordPendingReadReceiptForMessage:message
                                                                             thread:thread
                                                                        transaction:transaction.unwrapGrdbWrite];
            }
            break;
        case OWSReadCircumstanceReadOnThisDevice: {
            [self enqueueLinkedDeviceReadReceiptForMessage:message transaction:transaction];
            [transaction addAsyncCompletion:^{
                [self scheduleProcessing];
            }];

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
        case OWSReadCircumstanceReadOnThisDeviceWhilePendingMessageRequest:
            [self enqueueLinkedDeviceReadReceiptForMessage:message transaction:transaction];
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReadReceiptRecorder recordPendingReadReceiptForMessage:message
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
                               filter:^(TSInteraction *interaction) {
                                   return [interaction isKindOfClass:[TSMessage class]];
                               }
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
        OWSReadCircumstance circumstance = hasPendingMessageRequest
            ? OWSReadCircumstanceReadOnLinkedDeviceWhilePendingMessageRequest
            : OWSReadCircumstanceReadOnLinkedDevice;

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

#pragma mark - Mark As Read

- (void)markAsReadBeforeSortId:(uint64_t)sortId
                        thread:(TSThread *)thread
                 readTimestamp:(uint64_t)readTimestamp
                  circumstance:(OWSReadCircumstance)circumstance
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
              circumstance:(OWSReadCircumstance)circumstance
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(unreadMessages.count > 0);
    OWSAssertDebug(transaction);

    switch (circumstance) {
        case OWSReadCircumstanceReadOnLinkedDevice:
            OWSLogInfo(@"Marking %lu messages as read by linked device.", (unsigned long)unreadMessages.count);
            break;
        case OWSReadCircumstanceReadOnLinkedDeviceWhilePendingMessageRequest:
            OWSLogInfo(@"Marking %lu messages as read by linked device while pending message request.",
                (unsigned long)unreadMessages.count);
        case OWSReadCircumstanceReadOnThisDevice:
            OWSLogInfo(@"Marking %lu messages as read locally.", (unsigned long)unreadMessages.count);
            break;
        case OWSReadCircumstanceReadOnThisDeviceWhilePendingMessageRequest:
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
                @([OWSReadReceiptManager.keyValueStore getBool:OWSReadReceiptManagerAreReadReceiptsEnabled
                                                  defaultValue:NO
                                                   transaction:transaction]);
        }];
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (void)setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:(BOOL)value
{
    OWSLogInfo(@"setAreReadReceiptsEnabled: %d.", value);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self setAreReadReceiptsEnabled:value transaction:transaction];
    });

    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
    [SSKEnvironment.shared.storageServiceManager recordPendingLocalAccountUpdates];
}


- (void)setAreReadReceiptsEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction
{
    [OWSReadReceiptManager.keyValueStore setBool:value
                                             key:OWSReadReceiptManagerAreReadReceiptsEnabled
                                     transaction:transaction];
    self.areReadReceiptsEnabledCached = @(value);
}

@end

NS_ASSUME_NONNULL_END
