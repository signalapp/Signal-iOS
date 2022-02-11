//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSReceiptManager.h"
#import "AppReadiness.h"
#import "MessageSender.h"
#import "OWSLinkedDeviceReadReceipt.h"
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

        __block NSUInteger unreadCount;
        __block NSUInteger messagesWithUnreadReactionsCount;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            unreadCount = [interactionFinder countUnreadMessagesBeforeSortId:sortId
                                                                 transaction:transaction.unwrapGrdbRead];
            messagesWithUnreadReactionsCount =
                [interactionFinder countMessagesWithUnreadReactionsBeforeSortId:sortId
                                                                    transaction:transaction.unwrapGrdbRead];
        }];

        if (unreadCount == 0 && messagesWithUnreadReactionsCount == 0) {
            // Avoid unnecessary writes.
            dispatch_async(dispatch_get_main_queue(), completion);
            return;
        }

        SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
        uint64_t readTimestamp = [NSDate ows_millisecondTimeStamp];
        OWSReceiptCircumstance circumstance = hasPendingMessageRequest
            ? OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest
            : OWSReceiptCircumstanceOnThisDevice;

        // Mark as read in batches.
        const NSUInteger maxBatchSize = 500;

        NSString *reason;
        switch (circumstance) {
            case OWSReceiptCircumstanceOnLinkedDevice:
                reason = @"by linked device";
                break;
            case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
                reason = @"by linked device while pending message request";
                break;
            case OWSReceiptCircumstanceOnThisDevice:
                reason = @"locally";
                break;
            case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
                reason = @"locally while pending message request";
                break;
        }
        OWSLogInfo(
            @"Marking %lu received messages and %lu sent messages with reactions as read %@ (in batches of %lu).",
            (unsigned long)unreadCount,
            (unsigned long)messagesWithUnreadReactionsCount,
            reason,
            maxBatchSize);

        __block NSUInteger batchQuotaRemaining;
        do {
            batchQuotaRemaining = maxBatchSize;
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                [interactionFinder enumerateUnreadMessagesBeforeSortId:sortId
                                                           transaction:transaction.unwrapGrdbWrite
                                                                 block:^(id<OWSReadTracking> readItem, BOOL *stop) {
                                                                     [readItem markAsReadAtTimestamp:readTimestamp
                                                                                              thread:thread
                                                                                        circumstance:circumstance
                                                                                         transaction:transaction];
                                                                     --batchQuotaRemaining;
                                                                     if (batchQuotaRemaining == 0) {
                                                                         *stop = true;
                                                                     }
                                                                 }];
            });
            // Continue until we process a batch and have some quota left.
        } while (batchQuotaRemaining == 0);

        // Mark outgoing messages with unread reactions as well.
        do {
            batchQuotaRemaining = maxBatchSize;
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                NSMutableArray *receiptsForMessage = [[NSMutableArray alloc] init];
                [interactionFinder
                    enumerateMessagesWithUnreadReactionsBeforeSortId:sortId
                                                         transaction:transaction.unwrapGrdbWrite
                                                               block:^(TSOutgoingMessage *message, BOOL *stop) {
                                                                   [message markUnreadReactionsAsReadWithTransaction:
                                                                                transaction];
                                                                   OWSLinkedDeviceReadReceipt *receipt =
                                                                       [[OWSLinkedDeviceReadReceipt alloc]
                                                                           initWithSenderAddress:localAddress
                                                                                 messageUniqueId:message.uniqueId
                                                                              messageIdTimestamp:message.timestamp
                                                                                   readTimestamp:readTimestamp];
                                                                   [receiptsForMessage addObject:receipt];
                                                                   --batchQuotaRemaining;
                                                                   if (batchQuotaRemaining == 0) {
                                                                       *stop = true;
                                                                   }
                                                               }];

                if ([receiptsForMessage count] > 0) {
                    OWSReadReceiptsForLinkedDevicesMessage *message =
                        [[OWSReadReceiptsForLinkedDevicesMessage alloc] initWithThread:thread
                                                                          readReceipts:receiptsForMessage];
                    [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
                }
            });
            // Continue until we process a batch and have some quota left.
        } while (batchQuotaRemaining == 0);

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
                                                          messageUniqueId:message.uniqueId
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
                                                            messageUniqueId:message.uniqueId
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
                                        recipientDeviceId:(uint32_t)deviceId
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
                [message updateWithReadRecipient:address
                               recipientDeviceId:deviceId
                                   readTimestamp:readTimestamp
                                     transaction:transaction];
            }
        } else {
            [sentTimestampsMissingMessage addObject:@(sentTimestamp)];
        }
    }

    return [sentTimestampsMissingMessage copy];
}

- (NSArray<NSNumber *> *)processViewedReceiptsFromRecipient:(SignalServiceAddress *)address
                                          recipientDeviceId:(uint32_t)deviceId
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
                [message updateWithViewedRecipient:address
                                 recipientDeviceId:deviceId
                                   viewedTimestamp:viewedTimestamp
                                       transaction:transaction];
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
    [interactionFinder enumerateUnreadMessagesBeforeSortId:sortId
                                               transaction:transaction.unwrapGrdbWrite
                                                     block:^(id<OWSReadTracking> readItem, BOOL *_Nonnull stop) {
                                                         [readItem markAsReadAtTimestamp:readTimestamp
                                                                                  thread:thread
                                                                            circumstance:circumstance
                                                                             transaction:transaction];
                                                     }];
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
