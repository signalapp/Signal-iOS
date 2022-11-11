//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "ThreadUtil.h"
#import "OWSProfileManager.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/TSUnreadIndicatorInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ThreadUtil

#pragma mark - Durable Message Enqueue

+ (TSOutgoingMessage *)enqueueMessageWithInstalledSticker:(StickerInfo *)stickerInfo thread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo != nil);
    OWSAssertDebug(thread != nil);

    TSOutgoingMessage *message = [self buildOutgoingMessageForSticker:stickerInfo thread:thread];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Load the sticker data async.
        StickerMetadata *_Nullable stickerMetadata;
        stickerMetadata = [StickerManager installedStickerMetadataWithSneakyTransaction:stickerInfo];
        if (stickerMetadata == nil) {
            OWSFailDebug(@"Could not find sticker file.");
            return;
        }
        NSData *_Nullable stickerData = [NSData dataWithContentsOfURL:stickerMetadata.stickerDataUrl];
        if (!stickerData) {
            OWSFailDebug(@"Couldn't load sticker data.");
            return;
        }
        MessageStickerDraft *stickerDraft = [[MessageStickerDraft alloc] initWithInfo:stickerInfo
                                                                          stickerData:stickerData
                                                                          stickerType:stickerMetadata.stickerType
                                                                                emoji:stickerMetadata.firstEmoji];

        [self enqueueMessage:message stickerDraft:stickerDraft thread:thread];
    });

    return message;
}

+ (TSOutgoingMessage *)enqueueMessageWithUninstalledSticker:(StickerMetadata *)stickerMetadata
                                                stickerData:(NSData *)stickerData
                                                     thread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerMetadata != nil);
    OWSAssertDebug(stickerData.length > 0);
    OWSAssertDebug(thread != nil);

    TSOutgoingMessage *message = [self buildOutgoingMessageForSticker:stickerMetadata.stickerInfo thread:thread];
    MessageStickerDraft *stickerDraft = [[MessageStickerDraft alloc] initWithInfo:stickerMetadata.stickerInfo
                                                                      stickerData:stickerData
                                                                      stickerType:stickerMetadata.stickerType
                                                                            emoji:stickerMetadata.firstEmoji];

    [self enqueueMessage:message stickerDraft:stickerDraft thread:thread];

    return message;
}

+ (TSOutgoingMessage *)buildOutgoingMessageForSticker:(StickerInfo *)stickerInfo thread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo != nil);
    OWSAssertDebug(thread != nil);

    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];

    __block TSOutgoingMessage *message;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        builder.expiresInSeconds = [thread disappearingMessagesDurationWithTransaction:transaction];
        message = [builder buildWithTransaction:transaction];
    }];

    return message;
}

+ (void)enqueueMessage:(TSOutgoingMessage *)message
          stickerDraft:(MessageStickerDraft *)stickerDraft
                thread:(TSThread *)thread
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(stickerDraft != nil);
    OWSAssertDebug(thread != nil);

    [self enqueueSendAsyncWrite:^(SDSAnyWriteTransaction *transaction) {
        MessageSticker *_Nullable messageSticker = [self messageStickerForStickerDraft:stickerDraft
                                                                           transaction:transaction];
        if (!messageSticker) {
            OWSFailDebug(@"Couldn't send sticker.");
            return;
        }
        
        [message anyInsertWithTransaction:transaction];
        [message updateWithMessageSticker:messageSticker transaction:transaction];

        [self.sskJobQueues.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];

        [thread donateSendMessageIntentForOutgoingMessage:message transaction:transaction];
    }];
}

+ (nullable MessageSticker *)messageStickerForStickerDraft:(MessageStickerDraft *)stickerDraft
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSError *error;
    MessageSticker *_Nullable messageSticker = [MessageSticker buildValidatedMessageStickerFromDraft:stickerDraft
                                                                                         transaction:transaction
                                                                                               error:&error];
    if (error && ![MessageSticker isNoStickerError:error]) {
        OWSFailDebug(@"error: %@", error);
    }
    return messageSticker;
}

#pragma mark - Profile Whitelist

+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    __block BOOL hasPendingMessageRequest;
    __block BOOL needsDefaultTimerSet;
    __block DisappearingMessageToken *defaultTimerToken;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];

        defaultTimerToken =
            [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultUniversalConfigurationWithTransaction:transaction]
                .asToken;
        needsDefaultTimerSet =
            [GRDBThreadFinder shouldSetDefaultDisappearingMessageTimerWithThread:thread
                                                                     transaction:transaction.unwrapGrdbRead];
    }];

    if (needsDefaultTimerSet) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            OWSDisappearingMessagesConfiguration *configuration =
                [OWSDisappearingMessagesConfiguration applyToken:defaultTimerToken
                                                        toThread:thread
                                                     transaction:transaction];

            OWSDisappearingConfigurationUpdateInfoMessage *infoMessage =
                [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithThread:thread
                                                                        configuration:configuration
                                                                  createdByRemoteName:nil
                                                               createdInExistingGroup:NO];
            [infoMessage anyInsertWithTransaction:transaction];
        });
    }

    // If we're creating this thread or we have a pending message request,
    // any action we trigger should share our profile.
    if (!thread.shouldThreadBeVisible || hasPendingMessageRequest) {
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread];
        return YES;
    }

    return NO;
}

+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer:(TSThread *)thread
                                                                 transaction:(SDSAnyWriteTransaction *)transaction
{
    return [self addThreadToProfileWhitelistIfEmptyOrPendingRequest:thread
                                         setDefaultTimerIfNecessary:YES
                                                        transaction:transaction];
}

+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequest:(TSThread *)thread
                                setDefaultTimerIfNecessary:(BOOL)setDefaultTimerIfNecessary
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    DisappearingMessageToken *defaultTimerToken =
        [OWSDisappearingMessagesConfiguration fetchOrBuildDefaultUniversalConfigurationWithTransaction:transaction]
            .asToken;
    BOOL needsDefaultTimerSet =
        [GRDBThreadFinder shouldSetDefaultDisappearingMessageTimerWithThread:thread
                                                                 transaction:transaction.unwrapGrdbRead];

    if (needsDefaultTimerSet && setDefaultTimerIfNecessary) {
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration applyToken:defaultTimerToken toThread:thread transaction:transaction];

        OWSDisappearingConfigurationUpdateInfoMessage *infoMessage =
            [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithThread:thread
                                                                    configuration:configuration
                                                              createdByRemoteName:nil
                                                           createdInExistingGroup:NO];
        [infoMessage anyInsertWithTransaction:transaction];
    }

    BOOL hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
    // If we're creating this thread or we have a pending message request,
    // any action we trigger should share our profile.
    if (!thread.shouldThreadBeVisible || hasPendingMessageRequest) {
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread transaction:transaction];
        return YES;
    }

    return NO;
}

@end

NS_ASSUME_NONNULL_END
