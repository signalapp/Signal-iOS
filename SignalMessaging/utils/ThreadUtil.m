//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactsManager.h"
#import "OWSQuotedReplyModel.h"
#import "OWSUnreadIndicator.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/TSUnreadIndicatorInteraction.h>

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

#pragma mark -

typedef void (^BuildOutgoingMessageCompletionBlock)(TSOutgoingMessage *savedMessage,
    NSMutableArray<OWSOutgoingAttachmentInfo *> *attachmentInfos,
    SDSAnyWriteTransaction *writeTransaction);

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

+ (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
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
        configuration =
            [OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:thread.uniqueId transaction:transaction];
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

+ (TSOutgoingMessage *)enqueueMessageWithSticker:(StickerInfo *)stickerInfo inThread:(TSThread *)thread
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo);
    OWSAssertDebug(thread);

    __block OWSDisappearingMessagesConfiguration *configuration;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        configuration =
            [OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:thread.uniqueId transaction:transaction];
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
                                                       contactShare:nil
                                                        linkPreview:nil
                                                     messageSticker:nil
                                                  isViewOnceMessage:NO];

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
        MessageStickerDraft *stickerDraft =
            [[MessageStickerDraft alloc] initWithInfo:stickerInfo stickerData:stickerData];

        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            MessageSticker *_Nullable messageSticker =
                [self messageStickerForStickerDraft:stickerDraft transaction:transaction];
            if (!messageSticker) {
                OWSFailDebug(@"Couldn't send sticker.");
                return;
            }

            [message anyInsertWithTransaction:transaction];
            [message updateWithMessageSticker:messageSticker transaction:transaction];

            [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
        }];
    });

    return message;
}

+ (void)enqueueLeaveGroupMessageInThread:(TSGroupThread *)thread
{
    OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);

    TSOutgoingMessage *message =
        [TSOutgoingMessage outgoingMessageInThread:thread groupMetaMessage:TSGroupMetaMessageQuit expiresInSeconds:0];

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
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

    __block OWSDisappearingMessagesConfiguration *configuration;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        configuration =
            [OWSDisappearingMessagesConfiguration anyFetchWithUniqueId:thread.uniqueId transaction:transaction];
    }];

    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
    // MJK TODO - remove senderTimestamp
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

#pragma mark - Dynamic Interactions

+ (ThreadDynamicInteractions *)ensureDynamicInteractionsForThread:(TSThread *)thread
                                                  contactsManager:(OWSContactsManager *)contactsManager
                                                  blockingManager:(OWSBlockingManager *)blockingManager
                                      hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                                              lastUnreadIndicator:(nullable OWSUnreadIndicator *)lastUnreadIndicator
                                                   focusMessageId:(nullable NSString *)focusMessageId
                                                     maxRangeSize:(NSUInteger)maxRangeSize
                                                      transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(contactsManager);
    OWSAssertDebug(blockingManager);
    OWSAssertDebug(maxRangeSize > 0);
    OWSAssertDebug(transaction);

    ThreadDynamicInteractions *result = [ThreadDynamicInteractions new];

    // Find any "dynamic" interactions and safety number changes.
    //
    // We use different views for performance reasons.
    NSMutableArray<TSInvalidIdentityKeyErrorMessage *> *blockingSafetyNumberChanges = [NSMutableArray new];
    NSMutableArray<TSInteraction *> *nonBlockingSafetyNumberChanges = [NSMutableArray new];
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    // POSTYDB TODO: Make separate finder methods to find these messages.
    [interactionFinder
        enumerateSpecialMessagesWithTransaction:transaction
                                          block:^(TSInteraction *interaction, BOOL *stop) {
                                              if ([interaction
                                                      isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                                                  TSInvalidIdentityKeyErrorMessage *errorMessage
                                                      = (TSInvalidIdentityKeyErrorMessage *)interaction;
                                                  [blockingSafetyNumberChanges addObject:errorMessage];
                                              } else if ([interaction isKindOfClass:[TSErrorMessage class]]) {
                                                  TSErrorMessage *errorMessage = (TSErrorMessage *)interaction;
                                                  OWSAssertDebug(errorMessage.errorType
                                                      == TSErrorMessageNonBlockingIdentityChange);
                                                  [nonBlockingSafetyNumberChanges addObject:errorMessage];
                                              } else {
                                                  OWSFailDebug(
                                                      @"Unexpected dynamic interaction type: %@", [interaction class]);
                                              }
                                          }];

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
        NSError *error;
        __block TSInteraction *_Nullable firstUnseenInteraction;
        [interactionFinder enumerateUnseenInteractionsWithTransaction:transaction
                                                                error:&error
                                                                block:^(TSInteraction *interaction, BOOL *stop) {
                                                                    firstUnseenInteraction = interaction;
                                                                    *stop = YES;
                                                                }];
        if (error != nil) {
            OWSFailDebug(@"Error: %@", error);
        }
        if (firstUnseenInteraction) {
            firstUnseenSortId = @(firstUnseenInteraction.sortId);
        }
    }

    [self ensureUnreadIndicator:result
                                thread:thread
                           transaction:transaction
                          maxRangeSize:maxRangeSize
           blockingSafetyNumberChanges:blockingSafetyNumberChanges
        nonBlockingSafetyNumberChanges:nonBlockingSafetyNumberChanges
           hideUnreadMessagesIndicator:hideUnreadMessagesIndicator
                     firstUnseenSortId:firstUnseenSortId];

    // Determine the position of the focus message _after_ performing any mutations
    // around dynamic interactions.
    if (focusMessageId != nil) {
        result.focusMessagePosition =
            [self focusMessagePositionForThread:thread transaction:transaction focusMessageId:focusMessageId];
    }

    return result;
}

+ (void)ensureUnreadIndicator:(ThreadDynamicInteractions *)dynamicInteractions
                            thread:(TSThread *)thread
                       transaction:(SDSAnyReadTransaction *)transaction
                      maxRangeSize:(NSUInteger)maxRangeSize
       blockingSafetyNumberChanges:(NSArray<TSInvalidIdentityKeyErrorMessage *> *)blockingSafetyNumberChanges
    nonBlockingSafetyNumberChanges:(NSArray<TSInteraction *> *)nonBlockingSafetyNumberChanges
       hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                 firstUnseenSortId:(nullable NSNumber *)firstUnseenSortId
{
    OWSAssertDebug(dynamicInteractions);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(blockingSafetyNumberChanges);
    OWSAssertDebug(nonBlockingSafetyNumberChanges);

    if (hideUnreadMessagesIndicator) {
        return;
    }
    if (!firstUnseenSortId) {
        // If there are no unseen interactions, don't show an unread indicator.
        return;
    }

    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];

    // Determine unread indicator position, if necessary.
    //
    // Enumerate in reverse to count the number of messages
    // after the unseen messages indicator.  Not all of
    // them are unnecessarily unread, but we need to tell
    // the messages view the position of the unread indicator,
    // so that it can widen its "load window" to always show
    // the unread indicator.
    __block NSUInteger visibleUnseenMessageCount = 0;
    __block TSInteraction *interactionAfterUnreadIndicator = nil;
    __block BOOL hasMoreUnseenMessages = NO;
    NSError *error;
    [interactionFinder
        enumerateInteractionsWithTransaction:transaction
                                       error:&error
                                       block:^(TSInteraction *interaction, BOOL *stop) {
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
    if (error != nil) {
        OWSFailDebug(@"error: %@", error);
    }

    if (!interactionAfterUnreadIndicator) {
        // If we can't find an interaction after the unread indicator,
        // don't show it.  All unread messages may have been deleted or
        // expired.
        return;
    }
    OWSAssertDebug(visibleUnseenMessageCount > 0);

    NSUInteger missingUnseenSafetyNumberChangeCount = 0;
    if (hasMoreUnseenMessages) {
        NSMutableSet<NSData *> *missingUnseenSafetyNumberChanges = [NSMutableSet set];
        for (TSInvalidIdentityKeyErrorMessage *safetyNumberChange in blockingSafetyNumberChanges) {
            BOOL isUnseen = safetyNumberChange.sortId >= firstUnseenSortId.unsignedLongLongValue;
            if (!isUnseen) {
                continue;
            }

            BOOL isMissing = safetyNumberChange.sortId < interactionAfterUnreadIndicator.sortId;
            if (!isMissing) {
                continue;
            }

            @try {
                NSData *_Nullable newIdentityKey = [safetyNumberChange throws_newIdentityKey];
                if (newIdentityKey == nil) {
                    OWSFailDebug(@"Safety number change was missing it's new identity key.");
                    continue;
                }

                [missingUnseenSafetyNumberChanges addObject:newIdentityKey];
            } @catch (NSException *exception) {
                OWSFailDebug(@"exception: %@", exception);
            }
        }

        // Count the de-duplicated "blocking" safety number changes and all
        // of the "non-blocking" safety number changes.
        missingUnseenSafetyNumberChangeCount
            = (missingUnseenSafetyNumberChanges.count + nonBlockingSafetyNumberChanges.count);
    }

    OWSAssert(visibleUnseenMessageCount <= NSIntegerMax);
    NSInteger unreadIndicatorPosition = (NSInteger)visibleUnseenMessageCount;

    dynamicInteractions.unreadIndicator =
        [[OWSUnreadIndicator alloc] initWithFirstUnseenSortId:firstUnseenSortId.unsignedLongLongValue
                                        hasMoreUnseenMessages:hasMoreUnseenMessages
                         missingUnseenSafetyNumberChangeCount:missingUnseenSafetyNumberChangeCount
                                      unreadIndicatorPosition:unreadIndicatorPosition];
    OWSLogInfo(@"Creating Unread Indicator: %llu", dynamicInteractions.unreadIndicator.firstUnseenSortId);
}

+ (nullable NSNumber *)focusMessagePositionForThread:(TSThread *)thread
                                         transaction:(SDSAnyReadTransaction *)transaction
                                      focusMessageId:(NSString *)focusMessageId
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(focusMessageId);

    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    return [interactionFinder threadPositionForInteractionWithTransaction:transaction interactionId:focusMessageId];
}

+ (BOOL)addThreadToProfileWhitelistIfEmptyThreadWithSneakyTransaction:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.shouldThreadBeVisible) {
        return NO;
    }

    __block BOOL isThreadInProfileWhitelist;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        isThreadInProfileWhitelist =
            [OWSProfileManager.sharedManager isThreadInProfileWhitelist:thread transaction:transaction];
    }];
    if (isThreadInProfileWhitelist) {
        return NO;
    }

    [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];

    return YES;
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
    }];
    [TSAttachmentStream deleteAttachments];
}

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                 authorAddress:(SignalServiceAddress *)authorAddress
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorAddress.isValid);

    SignalServiceAddress *localAddress = TSAccountManager.localAddress;
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

#pragma mark - Message Request

+ (BOOL)hasPendingMessageRequest:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    // If we're creating the thread, don't show the message request view
    if (!thread.shouldThreadBeVisible) {
        return NO;
    }

    // If the thread is already whitelisted, do nothing. The user has already
    // accepted the request for this thread.
    if ([self.profileManager isThreadInProfileWhitelist:thread transaction:transaction]) {
        return NO;
    }

    BOOL hasSentMessages = [self existsOutgoingMessage:thread transaction:transaction];

    if (hasSentMessages && !SSKFeatureFlags.phoneNumberPrivacy) {
        return NO;
    }

    BOOL isThreadSystemContact = NO;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        // we want to check if the thread belongs to a system contact whether or not the thread's
        // user is still active signal account.
        isThreadSystemContact = [self.contactsManager isSystemContactWithAddress:contactThread.contactAddress];
    }

    // If this thread is a conversation with a system contact, add them to the profile
    // whitelist immediately and do not show the request dialog. People in your system
    // contacts get to bypass the message request flow.
    if (isThreadSystemContact) {
        [self.profileManager addThreadToProfileWhitelist:thread];
        return NO;
    }

    return YES;
}

+ (BOOL)existsOutgoingMessage:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    InteractionFinder *finder = [[InteractionFinder alloc] initWithThreadUniqueId:thread.uniqueId];
    return [finder existsOutgoingMessageWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
