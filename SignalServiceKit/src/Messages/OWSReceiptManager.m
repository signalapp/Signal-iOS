//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSReceiptManager.h"
#import "AppReadiness.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSReceiptsForSenderMessage.h"
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
                [self.outgoingReceiptManager enqueueReadReceiptFor:message.authorAddress
                                                         timestamp:message.timestamp
                                                   messageUniqueId:message.uniqueId
                                                                tx:transaction];
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
                [self.outgoingReceiptManager enqueueViewedReceiptFor:message.authorAddress
                                                           timestamp:message.timestamp
                                                     messageUniqueId:message.uniqueId
                                                                  tx:transaction];
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

- (void)storyWasRead:(StoryMessage *)storyMessage
        circumstance:(OWSReceiptCircumstance)circumstance
         transaction:(SDSAnyWriteTransaction *)transaction
{
    switch (circumstance) {
        case OWSReceiptCircumstanceOnLinkedDevice:
            // nothing further to do
            break;
        case OWSReceiptCircumstanceOnLinkedDeviceWhilePendingMessageRequest:
            OWSFailDebug(@"Unexpectedly had story receipt blocked by message request.");
            break;
        case OWSReceiptCircumstanceOnThisDevice: {
            // We only send read receipts to linked devices, not to the author.
            [self enqueueLinkedDeviceReadReceiptForStoryMessage:storyMessage transaction:transaction];
            [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];
            break;
        }
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            OWSFailDebug(@"Unexpectedly had story receipt blocked by message request.");
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
            OWSFailDebug(@"Unexpectedly had story receipt blocked by message request.");
            break;
        case OWSReceiptCircumstanceOnThisDevice: {
            [self enqueueLinkedDeviceViewedReceiptForStoryMessage:storyMessage transaction:transaction];
            [transaction addAsyncCompletionOffMain:^{ [self scheduleProcessing]; }];

            if (StoryManager.areViewReceiptsEnabled) {
                OWSLogVerbose(@"Enqueuing viewed receipt for sender.");
                [self enqueueSenderViewedReceiptForStoryMessage:storyMessage transaction:transaction];
            }
            break;
        }
        case OWSReceiptCircumstanceOnThisDeviceWhilePendingMessageRequest:
            OWSFailDebug(@"Unexpectedly had story receipt blocked by message request.");
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
        [self.databaseStorage
            readWithBlock:^(SDSAnyReadTransaction *transaction) {
                self.areReadReceiptsEnabledCached = @([self areReadReceiptsEnabledWithTransaction:transaction]);
            }
                     file:__FILE__
                 function:__FUNCTION__
                     line:__LINE__];
    }

    return [self.areReadReceiptsEnabledCached boolValue];
}

- (BOOL)areReadReceiptsEnabledWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSReceiptManager.keyValueStore getBool:OWSReceiptManagerAreReadReceiptsEnabled
                                       defaultValue:NO
                                        transaction:transaction];
}

- (void)setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration:(BOOL)value
{
    OWSLogInfo(@"setAreReadReceiptsEnabled: %d.", value);

    DatabaseStorageWrite(self.databaseStorage,
        ^(SDSAnyWriteTransaction *transaction) { [self setAreReadReceiptsEnabled:value transaction:transaction]; });

    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
    [SSKEnvironment.shared.storageServiceManagerObjc recordPendingLocalAccountUpdates];
}


- (void)setAreReadReceiptsEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction
{
    [OWSReceiptManager.keyValueStore setBool:value key:OWSReceiptManagerAreReadReceiptsEnabled transaction:transaction];
    self.areReadReceiptsEnabledCached = @(value);
}

@end

NS_ASSUME_NONNULL_END
