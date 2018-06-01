//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactOffersInteraction.h"
#import "OWSContactsManager.h"
#import "OWSQuotedReplyModel.h"
#import "TSUnreadIndicatorInteraction.h"
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThreadDynamicInteractions ()

@property (nonatomic, nullable) NSNumber *unreadIndicatorPosition;

@property (nonatomic, nullable) NSNumber *firstUnseenInteractionTimestamp;

@property (nonatomic) BOOL hasMoreUnseenMessages;

@end

#pragma mark -

@implementation ThreadDynamicInteractions

- (void)clearUnreadIndicatorState
{
    self.unreadIndicatorPosition = nil;
    self.firstUnseenInteractionTimestamp = nil;
    self.hasMoreUnseenMessages = NO;
}

@end

#pragma mark -

@implementation ThreadUtil

+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                          quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             messageSender:(OWSMessageSender *)messageSender
{
    return [self sendMessageWithText:text
        inThread:thread
        quotedReplyModel:quotedReplyModel
        messageSender:messageSender
        success:^{
            DDLogInfo(@"%@ Successfully sent message.", self.logTag);
        }
        failure:^(NSError *error) {
            DDLogWarn(@"%@ Failed to deliver message with error: %@", self.logTag, error);
        }];
}


+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                          quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             messageSender:(OWSMessageSender *)messageSender
                                   success:(void (^)(void))successHandler
                                   failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertIsOnMainThread();
    OWSAssert(text.length > 0);
    OWSAssert(thread);
    OWSAssert(messageSender);

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];
    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
    TSOutgoingMessage *message = [TSOutgoingMessage outgoingMessageInThread:thread
                                                                messageBody:text
                                                               attachmentId:nil
                                                           expiresInSeconds:expiresInSeconds
                                                              quotedMessage:[quotedReplyModel buildQuotedMessage]];

    [messageSender enqueueMessage:message success:successHandler failure:failureHandler];

    return message;
}

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                   messageSender:(OWSMessageSender *)messageSender
                                      completion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    return [self sendMessageWithAttachment:attachment
                                  inThread:thread
                          quotedReplyModel:quotedReplyModel
                             messageSender:messageSender
                              ignoreErrors:NO
                                completion:completion];
}

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                   messageSender:(OWSMessageSender *)messageSender
                                    ignoreErrors:(BOOL)ignoreErrors
                                      completion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();
    OWSAssert(attachment);
    OWSAssert(ignoreErrors || ![attachment hasError]);
    OWSAssert([attachment mimeType].length > 0);
    OWSAssert(thread);
    OWSAssert(messageSender);

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];

    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                        messageBody:attachment.captionText
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:expiresInSeconds
                                                    expireStartedAt:0
                                                     isVoiceMessage:[attachment isVoiceMessage]
                                                   groupMetaMessage:TSGroupMessageUnspecified
                                                      quotedMessage:[quotedReplyModel buildQuotedMessage]
                                                       contactShare:nil];

    [messageSender enqueueAttachment:attachment.dataSource
        contentType:attachment.mimeType
        sourceFilename:attachment.filenameOrDefault
        inMessage:message
        success:^{
            DDLogDebug(@"%@ Successfully sent message attachment.", self.logTag);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    completion(nil);
                });
            }
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send message attachment with error: %@", self.logTag, error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    completion(error);
                });
            }
        }];

    return message;
}

+ (TSOutgoingMessage *)sendMessageWithContactShare:(OWSContact *)contactShare
                                          inThread:(TSThread *)thread
                                     messageSender:(OWSMessageSender *)messageSender
                                        completion:(void (^_Nullable)(NSError *_Nullable error))completion
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);
    OWSAssert(contactShare.ows_isValid);
    OWSAssert(thread);
    OWSAssert(messageSender);

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];

    uint32_t expiresInSeconds = (configuration.isEnabled ? configuration.durationSeconds : 0);
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                           inThread:thread
                                                        messageBody:nil
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:expiresInSeconds
                                                    expireStartedAt:0
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMessageUnspecified
                                                      quotedMessage:nil
                                                       contactShare:contactShare];

    [messageSender enqueueMessage:message
        success:^{
            DDLogDebug(@"%@ Successfully sent contact share.", self.logTag);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    completion(nil);
                });
            }
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send contact share with error: %@", self.logTag, error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    completion(error);
                });
            }
        }];

    return message;
}

+ (ThreadDynamicInteractions *)ensureDynamicInteractionsForThread:(TSThread *)thread
                                                  contactsManager:(OWSContactsManager *)contactsManager
                                                  blockingManager:(OWSBlockingManager *)blockingManager
                                                     dbConnection:(YapDatabaseConnection *)dbConnection
                                      hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                                  firstUnseenInteractionTimestamp:
                                      (nullable NSNumber *)firstUnseenInteractionTimestampParameter
                                                     maxRangeSize:(int)maxRangeSize
{
    OWSAssert(thread);
    OWSAssert(dbConnection);
    OWSAssert(contactsManager);
    OWSAssert(blockingManager);
    OWSAssert(maxRangeSize > 0);

    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssert(localNumber.length > 0);

    // Many OWSProfileManager methods aren't safe to call from inside a database
    // transaction, so do this work now.
    OWSProfileManager *profileManager = OWSProfileManager.sharedManager;
    BOOL hasLocalProfile = [profileManager hasLocalProfile];
    BOOL isThreadInProfileWhitelist = [profileManager isThreadInProfileWhitelist:thread];
    BOOL hasUnwhitelistedMember = NO;
    for (NSString *recipientId in thread.recipientIdentifiers) {
        if (![profileManager isUserInProfileWhitelist:recipientId]) {
            hasUnwhitelistedMember = YES;
            break;
        }
    }

    ThreadDynamicInteractions *result = [ThreadDynamicInteractions new];

    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxBlockOfferOutgoingMessageCount = 10;

        // Find any "dynamic" interactions and safety number changes.
        //
        // We use different views for performance reasons.
        __block TSUnreadIndicatorInteraction *existingUnreadIndicator = nil;
        __block OWSContactOffersInteraction *existingContactOffers = nil;
        NSMutableArray<TSInvalidIdentityKeyErrorMessage *> *blockingSafetyNumberChanges = [NSMutableArray new];
        NSMutableArray<TSInteraction *> *nonBlockingSafetyNumberChanges = [NSMutableArray new];
        // We want to delete legacy and duplicate interactions.
        NSMutableArray<TSInteraction *> *interactionsToDelete = [NSMutableArray new];
        [[TSDatabaseView threadSpecialMessagesDatabaseView:transaction]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              // Delete this legacy interactions, which has been superseded by
                              // the OWSContactOffersInteraction.
                              [interactionsToDelete addObject:object];
                          } else if ([object isKindOfClass:[OWSAddToContactsOfferMessage class]]) {
                              // Delete this legacy interactions, which has been superseded by
                              // the OWSContactOffersInteraction.
                              [interactionsToDelete addObject:object];
                          } else if ([object isKindOfClass:[OWSAddToProfileWhitelistOfferMessage class]]) {
                              // Delete this legacy interactions, which has been superseded by
                              // the OWSContactOffersInteraction.
                              [interactionsToDelete addObject:object];
                          } else if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                              OWSAssert(!existingUnreadIndicator);
                              if (existingUnreadIndicator) {
                                  // There should never be more than one unread indicator in
                                  // a given thread, but if there is, discard all but one.
                                  [interactionsToDelete addObject:existingUnreadIndicator];
                              }
                              existingUnreadIndicator = (TSUnreadIndicatorInteraction *)object;
                          } else if ([object isKindOfClass:[OWSContactOffersInteraction class]]) {
                              OWSAssert(!existingContactOffers);
                              if (existingContactOffers) {
                                  // There should never be more than one "contact offers" in
                                  // a given thread, but if there is, discard all but one.
                                  [interactionsToDelete addObject:existingContactOffers];
                              }
                              existingContactOffers = (OWSContactOffersInteraction *)object;
                          } else if ([object isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                              [blockingSafetyNumberChanges addObject:object];
                          } else if ([object isKindOfClass:[TSErrorMessage class]]) {
                              TSErrorMessage *errorMessage = (TSErrorMessage *)object;
                              OWSAssert(errorMessage.errorType == TSErrorMessageNonBlockingIdentityChange);
                              [nonBlockingSafetyNumberChanges addObject:errorMessage];
                          } else {
                              OWSFail(@"Unexpected dynamic interaction type: %@", [object class]);
                          }
                      }];

        for (TSInteraction *interaction in interactionsToDelete) {
            DDLogDebug(@"Cleaning up interaction: %@", [interaction class]);
            [interaction removeWithTransaction:transaction];
        }

        // Determine if there are "unread" messages in this conversation.
        // If we've been passed a firstUnseenInteractionTimestampParameter,
        // just use that value in order to preserve continuity of the
        // unread messages indicator after all messages in the conversation
        // have been marked as read.
        //
        // IFF this variable is non-null, there are unseen messages in the thread.
        if (firstUnseenInteractionTimestampParameter) {
            result.firstUnseenInteractionTimestamp = firstUnseenInteractionTimestampParameter;
        } else {
            TSInteraction *_Nullable firstUnseenInteraction =
                [[TSDatabaseView unseenDatabaseViewExtension:transaction] firstObjectInGroup:thread.uniqueId];
            if (firstUnseenInteraction) {
                result.firstUnseenInteractionTimestamp = @(firstUnseenInteraction.timestampForSorting);
            }
        }

        __block TSInteraction *firstCallOrMessage = nil;
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          OWSAssert([object isKindOfClass:[TSInteraction class]]);

                          if ([object isKindOfClass:[TSIncomingMessage class]] ||
                              [object isKindOfClass:[TSOutgoingMessage class]] ||
                              [object isKindOfClass:[TSCall class]]) {
                              firstCallOrMessage = object;
                              *stop = YES;
                          }
                      }];

        NSUInteger outgoingMessageCount =
            [[TSDatabaseView threadOutgoingMessageDatabaseView:transaction] numberOfItemsInGroup:thread.uniqueId];
        NSUInteger threadMessageCount =
            [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];

        // Enumerate in reverse to count the number of messages
        // after the unseen messages indicator.  Not all of
        // them are unnecessarily unread, but we need to tell
        // the messages view the position of the unread indicator,
        // so that it can widen its "load window" to always show
        // the unread indicator.
        __block long visibleUnseenMessageCount = 0;
        __block TSInteraction *interactionAfterUnreadIndicator = nil;
        NSUInteger missingUnseenSafetyNumberChangeCount = 0;
        if (result.firstUnseenInteractionTimestamp != nil) {
            [[transaction ext:TSMessageDatabaseViewExtensionName]
                enumerateRowsInGroup:thread.uniqueId
                         withOptions:NSEnumerationReverse
                          usingBlock:^(NSString *collection,
                              NSString *key,
                              id object,
                              id metadata,
                              NSUInteger index,
                              BOOL *stop) {

                              if (![object isKindOfClass:[TSInteraction class]]) {
                                  OWSFail(@"Expected a TSInteraction: %@", [object class]);
                                  return;
                              }

                              TSInteraction *interaction = (TSInteraction *)object;

                              if (interaction.isDynamicInteraction) {
                                  // Ignore dynamic interactions, if any.
                                  return;
                              }

                              if (interaction.timestampForSorting
                                  < result.firstUnseenInteractionTimestamp.unsignedLongLongValue) {
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
                                  result.hasMoreUnseenMessages = YES;
                              }
                          }];

            if (!interactionAfterUnreadIndicator) {
                // If we can't find an interaction after the unread indicator,
                // remove it.  All unread messages may have been deleted or
                // expired.
                result.firstUnseenInteractionTimestamp = nil;
            } else if (result.hasMoreUnseenMessages) {
                NSMutableSet<NSData *> *missingUnseenSafetyNumberChanges = [NSMutableSet set];
                for (TSInvalidIdentityKeyErrorMessage *safetyNumberChange in blockingSafetyNumberChanges) {
                    BOOL isUnseen = safetyNumberChange.timestampForSorting
                        >= result.firstUnseenInteractionTimestamp.unsignedLongLongValue;
                    if (!isUnseen) {
                        continue;
                    }
                    BOOL isMissing
                        = safetyNumberChange.timestampForSorting < interactionAfterUnreadIndicator.timestampForSorting;
                    if (!isMissing) {
                        continue;
                    }

                    NSData *_Nullable newIdentityKey = safetyNumberChange.newIdentityKey;
                    if (newIdentityKey == nil) {
                        OWSFail(@"Safety number change was missing it's new identity key.");
                        continue;
                    }

                    [missingUnseenSafetyNumberChanges addObject:newIdentityKey];
                }

                // Count the de-duplicated "blocking" safety number changes and all
                // of the "non-blocking" safety number changes.
                missingUnseenSafetyNumberChangeCount
                    = (missingUnseenSafetyNumberChanges.count + nonBlockingSafetyNumberChanges.count);
            }
        }
        if (result.firstUnseenInteractionTimestamp) {
            // The unread indicator is _before_ the last visible unseen message.
            result.unreadIndicatorPosition = @(visibleUnseenMessageCount);
        }
        OWSAssert((result.firstUnseenInteractionTimestamp != nil) == (result.unreadIndicatorPosition != nil));

        BOOL shouldHaveBlockOffer = YES;
        BOOL shouldHaveAddToContactsOffer = YES;
        BOOL shouldHaveAddToProfileWhitelistOffer = YES;

        BOOL isContactThread = [thread isKindOfClass:[TSContactThread class]];
        if (!isContactThread) {
            // Only create "add to contacts" offers in 1:1 conversations.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers in 1:1 conversations.
            shouldHaveBlockOffer = NO;
            // Only create profile whitelist offers in 1:1 conversations.
            shouldHaveAddToProfileWhitelistOffer = NO;
        } else {
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            if ([recipientId isEqualToString:localNumber]) {
                // Don't add self to contacts.
                shouldHaveAddToContactsOffer = NO;
                // Don't bother to block self.
                shouldHaveBlockOffer = NO;
                // Don't bother adding self to profile whitelist.
                shouldHaveAddToProfileWhitelistOffer = NO;
            } else {
                if ([[blockingManager blockedPhoneNumbers] containsObject:recipientId]) {
                    // Only create "add to contacts" offers for users which are not already blocked.
                    shouldHaveAddToContactsOffer = NO;
                    // Only create block offers for users which are not already blocked.
                    shouldHaveBlockOffer = NO;
                    // Don't create profile whitelist offers for users which are not already blocked.
                    shouldHaveAddToProfileWhitelistOffer = NO;
                }

                if ([contactsManager hasSignalAccountForRecipientId:recipientId]) {
                    // Only create "add to contacts" offers for non-contacts.
                    shouldHaveAddToContactsOffer = NO;
                    // Only create block offers for non-contacts.
                    shouldHaveBlockOffer = NO;
                    // Don't create profile whitelist offers for non-contacts.
                    shouldHaveAddToProfileWhitelistOffer = NO;
                }
            }
        }

        if (!firstCallOrMessage) {
            shouldHaveAddToContactsOffer = NO;
            shouldHaveBlockOffer = NO;
            shouldHaveAddToProfileWhitelistOffer = NO;
        }

        if (outgoingMessageCount > kMaxBlockOfferOutgoingMessageCount) {
            // If the user has sent more than N messages, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        BOOL hasOutgoingBeforeIncomingInteraction = [firstCallOrMessage isKindOfClass:[TSOutgoingMessage class]];
        if ([firstCallOrMessage isKindOfClass:[TSCall class]]) {
            TSCall *call = (TSCall *)firstCallOrMessage;
            hasOutgoingBeforeIncomingInteraction
                = (call.callType == RPRecentCallTypeOutgoing || call.callType == RPRecentCallTypeOutgoingIncomplete);
        }
        if (hasOutgoingBeforeIncomingInteraction) {
            // If there is an outgoing message before an incoming message
            // the local user initiated this conversation, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        if (!hasLocalProfile || isThreadInProfileWhitelist) {
            // Don't show offer if thread is local user hasn't configured their profile.
            // Don't show offer if thread is already in profile whitelist.
            shouldHaveAddToProfileWhitelistOffer = NO;
        } else if (thread.isGroupThread && !hasUnwhitelistedMember) {
            // Don't show offer in group thread if all members are already individually
            // whitelisted.
            shouldHaveAddToProfileWhitelistOffer = NO;
        }

        BOOL shouldHaveContactOffers
            = (shouldHaveBlockOffer || shouldHaveAddToContactsOffer || shouldHaveAddToProfileWhitelistOffer);
        if (isContactThread) {
            TSContactThread *contactThread = (TSContactThread *)thread;
            if (contactThread.hasDismissedOffers) {
                shouldHaveContactOffers = NO;
            }
        }

        // We use these offset to control the ordering of the offers and indicators.
        const int kUnreadIndicatorOffset = -1;

        // We want the offers to be the first interactions in their
        // conversation's timeline, so we back-date them to slightly before
        // the first message - or at an aribtrary old timestamp if the
        // conversation has no messages.
        uint64_t contactOffersTimestamp = [NSDate ows_millisecondTimeStamp];

        // If the contact offers' properties have changed, discard the current
        // one and create a new one.
        if (existingContactOffers) {
            if (existingContactOffers.hasBlockOffer != shouldHaveBlockOffer
                || existingContactOffers.hasAddToContactsOffer != shouldHaveAddToContactsOffer
                || existingContactOffers.hasAddToProfileWhitelistOffer != shouldHaveAddToProfileWhitelistOffer) {
                DDLogInfo(@"%@ Removing stale contact offers: %@ (%llu)",
                    self.logTag,
                    existingContactOffers.uniqueId,
                    existingContactOffers.timestampForSorting);
                // Preserve the timestamp of the existing "contact offers" so that
                // we replace it in the same position in the timeline.
                contactOffersTimestamp = existingContactOffers.timestamp;
                [existingContactOffers removeWithTransaction:transaction];
                existingContactOffers = nil;
            }
        }

        if (existingContactOffers && !shouldHaveContactOffers) {
            DDLogInfo(@"%@ Removing contact offers: %@ (%llu)",
                self.logTag,
                existingContactOffers.uniqueId,
                existingContactOffers.timestampForSorting);
            [existingContactOffers removeWithTransaction:transaction];
        } else if (!existingContactOffers && shouldHaveContactOffers) {
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            TSInteraction *offersMessage =
                [[OWSContactOffersInteraction alloc] initContactOffersWithTimestamp:contactOffersTimestamp
                                                                             thread:thread
                                                                      hasBlockOffer:shouldHaveBlockOffer
                                                              hasAddToContactsOffer:shouldHaveAddToContactsOffer
                                                      hasAddToProfileWhitelistOffer:shouldHaveAddToProfileWhitelistOffer
                                                                        recipientId:recipientId];
            [offersMessage saveWithTransaction:transaction];

            DDLogInfo(@"%@ Creating contact offers: %@ (%llu)",
                self.logTag,
                offersMessage.uniqueId,
                offersMessage.timestampForSorting);
        }

        BOOL shouldHaveUnreadIndicator
            = (interactionAfterUnreadIndicator && !hideUnreadMessagesIndicator && threadMessageCount > 1);
        if (!shouldHaveUnreadIndicator) {
            if (existingUnreadIndicator) {
                DDLogInfo(@"%@ Removing obsolete TSUnreadIndicatorInteraction: %@",
                    self.logTag,
                    existingUnreadIndicator.uniqueId);
                [existingUnreadIndicator removeWithTransaction:transaction];
            }
        } else {
            // We want the unread indicator to appear just before the first unread incoming
            // message in the conversation timeline...
            //
            // ...unless we have a fixed timestamp for the unread indicator.
            uint64_t indicatorTimestamp
                = (uint64_t)((long long)interactionAfterUnreadIndicator.timestampForSorting + kUnreadIndicatorOffset);

            if (indicatorTimestamp && existingUnreadIndicator.timestampForSorting == indicatorTimestamp) {
                // Keep the existing indicator; it is in the correct position.
            } else {
                if (existingUnreadIndicator) {
                    DDLogInfo(@"%@ Removing TSUnreadIndicatorInteraction due to changed timestamp: %@",
                        self.logTag,
                        existingUnreadIndicator.uniqueId);
                    [existingUnreadIndicator removeWithTransaction:transaction];
                }

                TSUnreadIndicatorInteraction *indicator = [[TSUnreadIndicatorInteraction alloc]
                        initUnreadIndicatorWithTimestamp:indicatorTimestamp
                                                  thread:thread
                                   hasMoreUnseenMessages:result.hasMoreUnseenMessages
                    missingUnseenSafetyNumberChangeCount:missingUnseenSafetyNumberChangeCount];
                [indicator saveWithTransaction:transaction];

                DDLogInfo(@"%@ Creating TSUnreadIndicatorInteraction: %@ (%llu)",
                    self.logTag,
                    indicator.uniqueId,
                    indicator.timestampForSorting);
            }
        }
    }];

    return result;
}

+ (BOOL)shouldShowGroupProfileBannerInThread:(TSThread *)thread blockingManager:(OWSBlockingManager *)blockingManager
{
    OWSAssert(thread);
    OWSAssert(blockingManager);

    if (!thread.isGroupThread) {
        return NO;
    }
    if ([OWSProfileManager.sharedManager isThreadInProfileWhitelist:thread]) {
        return NO;
    }
    if (![OWSProfileManager.sharedManager hasLocalProfile]) {
        return NO;
    }
    BOOL hasUnwhitelistedMember = NO;
    NSArray<NSString *> *blockedPhoneNumbers = [blockingManager blockedPhoneNumbers];
    for (NSString *recipientId in thread.recipientIdentifiers) {
        if (![blockedPhoneNumbers containsObject:recipientId]
            && ![OWSProfileManager.sharedManager isUserInProfileWhitelist:recipientId]) {
            hasUnwhitelistedMember = YES;
            break;
        }
    }
    if (!hasUnwhitelistedMember) {
        return NO;
    }
    return YES;
}

+ (BOOL)addThreadToProfileWhitelistIfEmptyContactThread:(TSThread *)thread
{
    OWSAssert(thread);

    if (thread.isGroupThread) {
        return NO;
    }
    if ([OWSProfileManager.sharedManager isThreadInProfileWhitelist:thread]) {
        return NO;
    }
    if (!thread.hasEverHadMessage) {
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Delete Content

+ (void)deleteAllContent
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self removeAllObjectsInCollection:[TSThread collection] class:[TSThread class] transaction:transaction];
            [self removeAllObjectsInCollection:[TSInteraction collection]
                                         class:[TSInteraction class]
                                   transaction:transaction];
            [self removeAllObjectsInCollection:[TSAttachment collection]
                                         class:[TSAttachment class]
                                   transaction:transaction];
            [self removeAllObjectsInCollection:[SignalRecipient collection]
                                         class:[SignalRecipient class]
                                   transaction:transaction];
        }];
    [TSAttachmentStream deleteAttachments];
}

+ (void)removeAllObjectsInCollection:(NSString *)collection
                               class:(Class) class
                         transaction:(YapDatabaseReadWriteTransaction *)transaction {
    OWSAssert(collection.length > 0);
    OWSAssert(class);
    OWSAssert(transaction);

    NSArray<NSString *> *_Nullable uniqueIds = [transaction allKeysInCollection:collection];
    if (!uniqueIds) {
        OWSProdLogAndFail(@"%@ couldn't load uniqueIds for collection: %@.", self.logTag, collection);
        return;
    }
    DDLogInfo(@"%@ Deleting %zd objects from: %@", self.logTag, uniqueIds.count, collection);
    NSUInteger count = 0;
    for (NSString *uniqueId in uniqueIds) {
        // We need to fetch each object, since [TSYapDatabaseObject removeWithTransaction:] sometimes does important
        // work.
        TSYapDatabaseObject *_Nullable object = [class fetchObjectWithUniqueID:uniqueId transaction:transaction];
        if (!object) {
            OWSProdLogAndFail(@"%@ couldn't load object for deletion: %@.", self.logTag, collection);
            continue;
        }
        [object removeWithTransaction:transaction];
        count++;
    };
    DDLogInfo(@"%@ Deleted %zd/%zd objects from: %@", self.logTag, count, uniqueIds.count, collection);
}

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                      authorId:(NSString *)authorId
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    NSString *localNumber = [TSAccountManager localNumber];
    if (localNumber.length < 1) {
        OWSFail(@"%@ missing long number.", self.logTag);
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
        DDLogError(@"%@ more than one matching interaction in thread.", self.logTag);
    }
    return interactions.firstObject;
}

@end

NS_ASSUME_NONNULL_END
