//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSQuotedReplyModel.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
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
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark - Durable Message Enqueue

+ (TSOutgoingMessage *)enqueueMessageWithText:(NSString *)fullMessageText
                                     inThread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self enqueueMessageWithText:fullMessageText
                       mediaAttachments:@[]
                               inThread:thread
                       quotedReplyModel:quotedReplyModel
                       linkPreviewDraft:linkPreviewDraft
                            transaction:transaction];
}

+ (TSOutgoingMessage *)enqueueMessageWithText:(nullable NSString *)fullMessageText
                             mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                     inThread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithFullMessageText:fullMessageText
                                                mediaAttachments:mediaAttachments
                                                          thread:thread
                                                quotedReplyModel:quotedReplyModel
                                                     transaction:transaction];

    [BenchManager benchAsyncWithTitle:@"Saving outgoing message"
                                block:^(void (^benchmarkCompletion)(void)) {
                                    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
                                        [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:writeTransaction];
                                        [self.messageSenderJobQueue addMessage:outgoingMessagePreparer transaction:writeTransaction];
                                    }
                                                                   completion:benchmarkCompletion];
                                }];

    return outgoingMessagePreparer.unpreparedMessage;
}

+ (nullable TSOutgoingMessage *)createUnsentMessageWithText:(nullable NSString *)fullMessageText
                                           mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                                   inThread:(TSThread *)thread
                                           quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                           linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                                transaction:(SDSAnyWriteTransaction *)transaction
                                                      error:(NSError **)error
{
    OWSAssertDebug(thread);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithFullMessageText:fullMessageText
                                                mediaAttachments:mediaAttachments
                                                          thread:thread
                                                quotedReplyModel:quotedReplyModel
                                                     transaction:transaction];

    [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:transaction];

    return [outgoingMessagePreparer prepareMessageWithTransaction:transaction error:error];
}

+ (TSOutgoingMessage *)enqueueMessageWithContactShare:(OWSContact *)contactShare inThread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);
    OWSAssertDebug(contactShare.ows_isValid);
    OWSAssertDebug(thread);

    __block OWSDisappearingMessagesConfiguration *configuration;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        configuration = [thread disappearingMessagesConfigurationWithTransaction:transaction];
    }];

    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:expiresInSeconds
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:contactShare
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [message anyInsertWithTransaction:transaction];
        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];

    return message;
}

+ (TSOutgoingMessage *)enqueueMessageWithInstalledSticker:(StickerInfo *)stickerInfo inThread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo != nil);
    OWSAssertDebug(thread != nil);

    TSOutgoingMessage *message = [self buildOutgoingMessageForSticker:stickerInfo thread:thread];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Load the sticker data async.
        NSString *_Nullable filePath = [StickerManager filepathForInstalledStickerWithStickerInfo:stickerInfo];
        if (!filePath) {
            OWSFailDebug(@"Could not find sticker file.");
            return;
        }
        NSData *_Nullable stickerData = [NSData dataWithContentsOfFile:filePath];
        if (!stickerData) {
            OWSFailDebug(@"Couldn't load sticker data.");
            return;
        }
        MessageStickerDraft *stickerDraft = [[MessageStickerDraft alloc] initWithInfo:stickerInfo
                                                                          stickerData:stickerData];

        [self enqueueMessage:message stickerDraft:stickerDraft thread:thread];
    });

    return message;
}

+ (TSOutgoingMessage *)enqueueMessageWithUninstalledSticker:(StickerInfo *)stickerInfo
                                                stickerData:(NSData *)stickerData
                                                   inThread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo != nil);
    OWSAssertDebug(stickerData.length > 0);
    OWSAssertDebug(thread != nil);

    TSOutgoingMessage *message = [self buildOutgoingMessageForSticker:stickerInfo thread:thread];

    MessageStickerDraft *stickerDraft = [[MessageStickerDraft alloc] initWithInfo:stickerInfo stickerData:stickerData];

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

    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:nil
                                                         attachmentIds:[NSMutableArray new]
                                                      expiresInSeconds:expiresInSeconds
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:TSGroupMetaMessageUnspecified
                                                         quotedMessage:nil
                                                          contactShare:nil
                                                           linkPreview:nil
                                                        messageSticker:nil
                                                     isViewOnceMessage:NO];
}

+ (void)enqueueMessage:(TSOutgoingMessage *)message
          stickerDraft:(MessageStickerDraft *)stickerDraft
                thread:(TSThread *)thread
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(stickerDraft != nil);
    OWSAssertDebug(thread != nil);

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        MessageSticker *_Nullable messageSticker = [self messageStickerForStickerDraft:stickerDraft
                                                                           transaction:transaction];
        if (!messageSticker) {
            OWSFailDebug(@"Couldn't send sticker.");
            return;
        }

        [message anyInsertWithTransaction:transaction];
        [message updateWithMessageSticker:messageSticker transaction:transaction];

        [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
    }];
}

// MARK: Non-Durable Sending

// We might want to generate a link preview here.
+ (TSOutgoingMessage *)sendMessageNonDurablyWithText:(NSString *)fullMessageText
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                         transaction:(SDSAnyReadTransaction *)transaction
                                       messageSender:(OWSMessageSender *)messageSender
                                          completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertDebug(completion);

    return [self sendMessageNonDurablyWithText:fullMessageText
                              mediaAttachments:@[]
                                      inThread:thread
                              quotedReplyModel:quotedReplyModel
                                   transaction:transaction
                                 messageSender:messageSender
                                    completion:completion];
}

+ (TSOutgoingMessage *)sendMessageNonDurablyWithText:(NSString *)fullMessageText
                                    mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                         transaction:(SDSAnyReadTransaction *)transaction
                                       messageSender:(OWSMessageSender *)messageSender
                                          completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(thread);
    OWSAssertDebug(completion);

    OutgoingMessagePreparer *outgoingMessagePreparer =
        [[OutgoingMessagePreparer alloc] initWithFullMessageText:fullMessageText
                                                mediaAttachments:mediaAttachments
                                                          thread:thread
                                                quotedReplyModel:quotedReplyModel
                                                     transaction:transaction];

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
        [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:nil transaction:writeTransaction];

        [messageSender sendMessage:outgoingMessagePreparer
            success:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil);
                });
            }
            failure:^(NSError *_Nonnull error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(error);
                });
            }];
    }];

    return outgoingMessagePreparer.unpreparedMessage;
}

+ (TSOutgoingMessage *)sendMessageNonDurablyWithContactShare:(OWSContact *)contactShare
                                                    inThread:(TSThread *)thread
                                               messageSender:(OWSMessageSender *)messageSender
                                                  completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);
    OWSAssertDebug(contactShare.ows_isValid);
    OWSAssertDebug(thread);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(completion);

    __block TSOutgoingMessage *message;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        OWSDisappearingMessagesConfiguration *configuration = [thread disappearingMessagesConfigurationWithTransaction:transaction];
        uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
        // MJK TODO - remove senderTimestamp
        message =
            [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                               inThread:thread
                                                            messageBody:nil
                                                          attachmentIds:[NSMutableArray new]
                                                       expiresInSeconds:expiresInSeconds
                                                        expireStartedAt:0
                                                         isVoiceMessage:NO
                                                       groupMetaMessage:TSGroupMetaMessageUnspecified
                                                          quotedMessage:nil
                                                           contactShare:contactShare
                                                            linkPreview:nil
                                                         messageSticker:nil
                                                      isViewOnceMessage:NO];
        [message anyInsertWithTransaction:transaction];
    }];

    [messageSender sendMessage:message.asPreparer
        success:^{
            OWSLogDebug(@"Successfully sent contact share.");
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                completion(nil);
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to send contact share with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                completion(error);
            });
        }];

    return message;
}

+ (nullable MessageSticker *)messageStickerForStickerDraft:(MessageStickerDraft *)stickerDraft
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSError *error;
    MessageSticker *_Nullable messageSticker =
        [MessageSticker buildValidatedMessageStickerFromDraft:stickerDraft transaction:transaction error:&error];
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
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
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
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread transaction:transaction];
        return YES;
    }

    return NO;
}

#pragma mark - Delete Content

+ (void)deleteAllContent
{
    OWSLogInfo(@"");

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [TSThread anyRemoveAllWithInstantationWithTransaction:transaction];
        [TSInteraction anyRemoveAllWithInstantationWithTransaction:transaction];
        [TSAttachment anyRemoveAllWithInstantationWithTransaction:transaction];
        [SignalRecipient anyRemoveAllWithInstantationWithTransaction:transaction];

        // Deleting attachments above should be enough to remove any gallery items, but
        // we redunantly clean up *all* gallery items to be safe.
        [AnyMediaGalleryFinder didRemoveAllContentWithTransaction:transaction];
    }];
    [TSAttachmentStream deleteAttachmentsFromDisk];
}

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                 authorAddress:(SignalServiceAddress *)authorAddress
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorAddress.isValid);

    SignalServiceAddress *_Nullable localAddress = [self.tsAccountManager localAddressWithTransaction:transaction];
    if (!localAddress.isValid) {
        OWSFailDebug(@"missing local address.");
        return nil;
    }

    BOOL (^filter)(TSInteraction *) = ^(TSInteraction *interaction) {
        SignalServiceAddress *_Nullable messageAuthorAddress = nil;
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)interaction;
            messageAuthorAddress = incomingMessage.authorAddress;
        } else if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
            messageAuthorAddress = localAddress;
        }
        if (!messageAuthorAddress.isValid) {
            return NO;
        }

        if (![authorAddress isEqualToAddress:messageAuthorAddress]) {
            return NO;
        }
        if (![interaction.uniqueThreadId isEqualToString:threadUniqueId]) {
            return NO;
        }
        return YES;
    };

    NSError *error;
    NSArray<TSInteraction *> *interactions =
        [InteractionFinder interactionsWithTimestamp:timestamp filter:filter transaction:transaction error:&error];
    if (error != nil) {
        OWSFailDebug(@"Error loading interactions: %@", error);
    }

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
