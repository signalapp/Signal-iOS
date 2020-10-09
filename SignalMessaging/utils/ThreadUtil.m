//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSQuotedReplyModel.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/OWSProfileManager.h>
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

#pragma mark - Dependencies

+ (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
}

+ (OWSProfileManager *)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

+ (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

+ (MessageSender *)messageSender
{
    return SSKEnvironment.shared.messageSender;
}

#pragma mark - Durable Message Enqueue

+ (TSOutgoingMessage *)enqueueMessageWithBody:(MessageBody *)messageBody
                                       thread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self enqueueMessageWithBody:messageBody
                       mediaAttachments:@[]
                                 thread:thread
                       quotedReplyModel:quotedReplyModel
                       linkPreviewDraft:linkPreviewDraft
                            transaction:transaction];
}

+ (TSOutgoingMessage *)enqueueMessageWithBody:(nullable MessageBody *)messageBody
                             mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                       thread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithMessageBody:messageBody
                                            mediaAttachments:mediaAttachments
                                                      thread:thread
                                            quotedReplyModel:quotedReplyModel
                                                 transaction:transaction];

    [BenchManager benchAsyncWithTitle:@"Saving outgoing message"
                                block:^(void (^benchmarkCompletion)(void)) {
                                    DatabaseStorageAsyncWrite(
                                        SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *writeTransaction) {
                                            [outgoingMessagePreparer
                                                insertMessageWithLinkPreviewDraft:linkPreviewDraft
                                                                      transaction:writeTransaction];
                                            [self.messageSenderJobQueue addMessage:outgoingMessagePreparer
                                                                       transaction:writeTransaction];

                                            [writeTransaction addAsyncCompletion:benchmarkCompletion];
                                        });
                                }];

    return outgoingMessagePreparer.unpreparedMessage;
}

+ (nullable TSOutgoingMessage *)createUnsentMessageWithBody:(nullable MessageBody *)messageBody
                                           mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                                     thread:(TSThread *)thread
                                           quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                           linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                                transaction:(SDSAnyWriteTransaction *)transaction
                                                      error:(NSError **)error
{
    OWSAssertDebug(thread);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithMessageBody:messageBody
                                            mediaAttachments:mediaAttachments
                                                      thread:thread
                                            quotedReplyModel:quotedReplyModel
                                                 transaction:transaction];

    [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:transaction];

    return [outgoingMessagePreparer prepareMessageWithTransaction:transaction error:error];
}

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

    __block OWSDisappearingMessagesConfiguration *configuration;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        configuration = [thread disappearingMessagesConfigurationWithTransaction:transaction];
    }];

    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);

    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    builder.expiresInSeconds = expiresInSeconds;
    return [builder build];
}

+ (void)enqueueMessage:(TSOutgoingMessage *)message
          stickerDraft:(MessageStickerDraft *)stickerDraft
                thread:(TSThread *)thread
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(stickerDraft != nil);
    OWSAssertDebug(thread != nil);

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        MessageSticker *_Nullable messageSticker = [self messageStickerForStickerDraft:stickerDraft
                                                                           transaction:transaction];
        if (!messageSticker) {
            OWSFailDebug(@"Couldn't send sticker.");
            return;
        }
        
        [message anyInsertWithTransaction:transaction];
        [message updateWithMessageSticker:messageSticker transaction:transaction];
        
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    });
}

// MARK: Non-Durable Sending

// We might want to generate a link preview here.
+ (TSOutgoingMessage *)sendMessageNonDurablyWithBody:(MessageBody *)messageBody
                                              thread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                    linkPreviewDraft:(nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                         transaction:(SDSAnyReadTransaction *)transaction
                                          completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertDebug(completion);

    return [self sendMessageNonDurablyWithBody:messageBody
                              mediaAttachments:@[]
                                        thread:thread
                              quotedReplyModel:quotedReplyModel
                              linkPreviewDraft:linkPreviewDraft
                                   transaction:transaction
                                    completion:completion];
}

+ (TSOutgoingMessage *)sendMessageNonDurablyWithBody:(MessageBody *)messageBody
                                    mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                              thread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                    linkPreviewDraft:(nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                         transaction:(SDSAnyReadTransaction *)transaction
                                          completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);
    OWSAssertDebug(completion);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithMessageBody:messageBody
                                            mediaAttachments:mediaAttachments
                                                      thread:thread
                                            quotedReplyModel:quotedReplyModel
                                                 transaction:transaction];

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTransaction) {
        [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:writeTransaction];

        [writeTransaction addAsyncCompletionOffMain:^{
            [self.messageSender sendMessage:outgoingMessagePreparer
                success:^{ dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
                failure:^(
                    NSError *_Nonnull error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(error); }); }];
        }];
    });

    return outgoingMessagePreparer.unpreparedMessage;
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

+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    __block BOOL hasPendingMessageRequest;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
    }];

    // If we're creating this thread or we have a pending message request,
    // any action we trigger should share our profile.
    if (!thread.shouldThreadBeVisible || hasPendingMessageRequest) {
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread];
        return YES;
    }

    return NO;
}

+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequest:(TSThread *)thread
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(thread);

    BOOL hasPendingMessageRequest = [thread hasPendingMessageRequestWithTransaction:transaction.unwrapGrdbRead];
    // If we're creating this thread or we have a pending message request,
    // any action we trigger should share our profile.
    if (!thread.shouldThreadBeVisible || hasPendingMessageRequest) {
        [OWSProfileManager.shared addThreadToProfileWhitelist:thread transaction:transaction];
        return YES;
    }

    return NO;
}

#pragma mark - Delete Content

+ (void)deleteAllContent
{
    OWSLogInfo(@"");

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [TSThread anyRemoveAllWithInstantationWithTransaction:transaction];
        [TSInteraction anyRemoveAllWithInstantationWithTransaction:transaction];
        [TSAttachment anyRemoveAllWithInstantationWithTransaction:transaction];
        [SignalRecipient anyRemoveAllWithInstantationWithTransaction:transaction];
        
        // Deleting attachments above should be enough to remove any gallery items, but
        // we redunantly clean up *all* gallery items to be safe.
        [AnyMediaGalleryFinder didRemoveAllContentWithTransaction:transaction];
    });
    [TSAttachmentStream deleteAttachmentsFromDisk];
}

@end

NS_ASSUME_NONNULL_END
