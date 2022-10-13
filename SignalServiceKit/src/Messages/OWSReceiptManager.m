//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
            [self enqueueLinkedDeviceViewedReceiptForIncomingMessage:message transaction:transaction];
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
            [self enqueueLinkedDeviceViewedReceiptForIncomingMessage:message transaction:transaction];
            if ([self areReadReceiptsEnabled]) {
                [self.pendingReceiptRecorder recordPendingViewedReceiptForMessage:message
                                                                           thread:thread
                                                                      transaction:transaction.unwrapGrdbWrite];
            }
            break;
    }
}

- (void)storyWasViewed:(StoryMessage *)storyMessage
          circumstance:(OWSReceiptCircumstance)circumstance
           transaction:(SDSAnyWriteTransaction *)transaction
{
    switch (circumstance) {
        case OWSReceiptCircumstanceOnLinkedDevice:
            // nothing further to do
            break;
        case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
            OWSFailDebug(@"Unexectedly had story receipt blocked by message request.");
            break;
        case OWSReceiptCircumstanceOnThisDevice: {
            [self enqueueLinkedDeviceViewedReceiptForStoryMessage:storyMessage transaction:transaction];
            [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];

            if ([self areReadReceiptsEnabled]) {
                OWSLogVerbose(@"Enqueuing viewed receipt for sender.");
                [self enqueueSenderViewedReceiptForStoryMessage:storyMessage transaction:transaction];
            }
            break;
        }
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            OWSFailDebug(@"Unexectedly had story receipt blocked by message request.");
            break;
    }
}

- (void)incomingGiftWasRedeemed:(TSIncomingMessage *)incomingMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueLinkedDeviceViewedReceiptForIncomingMessage:incomingMessage transaction:transaction];
    [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];
}

- (void)outgoingGiftWasOpened:(TSOutgoingMessage *)outgoingMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    [self enqueueLinkedDeviceViewedReceiptForOutgoingMessage:outgoingMessage transaction:transaction];
    [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];
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
            StoryMessage *_Nullable storyMessage = [StoryFinder storyWithTimestamp:sentTimestamp
                                                                            author:TSAccountManager.localAddress
                                                                       transaction:transaction];
            if (storyMessage) {
                [storyMessage markAsViewedAt:viewedTimestamp by:address transaction:transaction];
            } else {
                [sentTimestampsMissingMessage addObject:@(sentTimestamp)];
            }
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

        OWSLogInfo(@"Marking %lu messages as read on linked device. Timestamp: %llu",
            (unsigned long)messages.count,
            messageIdTimestamp);

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

        if (messageIdTimestamp == 0) {
            OWSFailDebug(@"messageIdTimestamp was unexpectedly 0");
            continue;
        }
        if (![SDS fitsInInt64:messageIdTimestamp]) {
            OWSFailDebug(@"Invalid messageIdTimestamp.");
            continue;
        }
        if (!senderAddress.isValid) {
            OWSFailDebug(@"senderAddress was unexpectedly %@", senderAddress != nil ? @"invalid" : @"nil");
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
            StoryMessage *_Nullable storyMessage = [StoryFinder storyWithTimestamp:messageIdTimestamp
                                                                            author:senderAddress
                                                                       transaction:transaction];
            if (storyMessage) {
                [storyMessage markAsViewedAt:viewedTimestamp
                                circumstance:OWSReceiptCircumstanceOnLinkedDevice
                                 transaction:transaction];
            } else {
                [receiptsMissingMessage addObject:viewedReceiptProto];
            }
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

    if (message.giftBadge != nil) {
        [message anyUpdateMessageWithTransaction:transaction
                                           block:^(TSMessage *_Nonnull obj) {
                                               if ([obj isKindOfClass:[TSIncomingMessage class]]) {
                                                   obj.giftBadge.redemptionState = OWSGiftBadgeRedemptionStateRedeemed;
                                               } else if ([obj isKindOfClass:[TSOutgoingMessage class]]) {
                                                   obj.giftBadge.redemptionState = OWSGiftBadgeRedemptionStateOpened;
                                               } else {
                                                   OWSFailDebug(@"Unexpected giftBadge message");
                                               }
                                           }];
        return;
    }

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
        } file:__FILE__ function:__FUNCTION__ line:__LINE__];
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
