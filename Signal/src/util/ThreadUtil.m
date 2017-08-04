//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "TSUnreadIndicatorInteraction.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/TSDatabaseView.h>
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
                             messageSender:(OWSMessageSender *)messageSender
{
    return [self sendMessageWithText:text
        inThread:thread
        messageSender:messageSender
        success:^{
            DDLogInfo(@"%@ Successfully sent message.", self.tag);
        }
        failure:^(NSError *error) {
            DDLogWarn(@"%@ Failed to deliver message with error: %@", self.tag, error);
        }];
}


+ (TSOutgoingMessage *)sendMessageWithText:(NSString *)text
                                  inThread:(TSThread *)thread
                             messageSender:(OWSMessageSender *)messageSender
                                   success:(void (^)())successHandler
                                   failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(text.length > 0);
    OWSAssert(thread);
    OWSAssert(messageSender);

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                            inThread:thread
                                         messageBody:text
                                       attachmentIds:[NSMutableArray new]
                                    expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];

    [messageSender sendMessage:message success:successHandler failure:failureHandler];

    return message;
}

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                   messageSender:(OWSMessageSender *)messageSender
{
    return [self sendMessageWithAttachment:attachment inThread:thread messageSender:messageSender ignoreErrors:NO];
}

+ (TSOutgoingMessage *)sendMessageWithAttachment:(SignalAttachment *)attachment
                                        inThread:(TSThread *)thread
                                   messageSender:(OWSMessageSender *)messageSender
                                    ignoreErrors:(BOOL)ignoreErrors
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(attachment);
    OWSAssert(ignoreErrors || ![attachment hasError]);
    OWSAssert([attachment mimeType].length > 0);
    OWSAssert(thread);
    OWSAssert(messageSender);

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];
    TSOutgoingMessage *message =
        [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                            inThread:thread
                                      isVoiceMessage:[attachment isVoiceMessage]
                                    expiresInSeconds:(configuration.isEnabled ? configuration.durationSeconds : 0)];
    [messageSender sendAttachmentData:attachment.data
        contentType:attachment.mimeType
        sourceFilename:attachment.filenameOrDefault
        inMessage:message
        success:^{
            DDLogDebug(@"%@ Successfully sent message attachment.", self.tag);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send message attachment with error: %@", self.tag, error);
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

    ThreadDynamicInteractions *result = [ThreadDynamicInteractions new];

    [dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxBlockOfferOutgoingMessageCount = 10;

        // Find any "dynamic" interactions and safety number changes.
        __block OWSAddToContactsOfferMessage *existingAddToContactsOffer = nil;
        __block OWSAddToProfileWhitelistOfferMessage *existingOWSAddToProfileWhitelistOffer = nil;
        __block OWSUnknownContactBlockOfferMessage *existingBlockOffer = nil;
        __block TSUnreadIndicatorInteraction *existingUnreadIndicator = nil;
        NSMutableArray<TSInvalidIdentityKeyErrorMessage *> *blockingSafetyNumberChanges = [NSMutableArray new];
        NSMutableArray<TSInteraction *> *nonBlockingSafetyNumberChanges = [NSMutableArray new];
        // We use different views for performance reasons.
        [[TSDatabaseView threadSpecialMessagesDatabaseView:transaction]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              OWSAssert(!existingBlockOffer);
                              existingBlockOffer = (OWSUnknownContactBlockOfferMessage *)object;
                          } else if ([object isKindOfClass:[OWSAddToContactsOfferMessage class]]) {
                              OWSAssert(!existingAddToContactsOffer);
                              existingAddToContactsOffer = (OWSAddToContactsOfferMessage *)object;
                          } else if ([object isKindOfClass:[OWSAddToProfileWhitelistOfferMessage class]]) {
                              OWSAssert(!existingOWSAddToProfileWhitelistOffer);
                              existingOWSAddToProfileWhitelistOffer = (OWSAddToProfileWhitelistOfferMessage *)object;
                          } else if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                              OWSAssert(!existingUnreadIndicator);
                              existingUnreadIndicator = (TSUnreadIndicatorInteraction *)object;
                          } else if ([object isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                              [blockingSafetyNumberChanges addObject:object];
                          } else if ([object isKindOfClass:[TSErrorMessage class]]) {
                              TSErrorMessage *errorMessage = (TSErrorMessage *)object;
                              OWSAssert(errorMessage.errorType == TSErrorMessageNonBlockingIdentityChange);
                              [nonBlockingSafetyNumberChanges addObject:errorMessage];
                          } else {
                              DDLogError(@"Unexpected dynamic interaction type: %@", [object class]);
                              OWSAssert(0);
                          }
                      }];

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
            TSInteraction *firstUnseenInteraction =
                [[TSDatabaseView unseenDatabaseViewExtension:transaction] firstObjectInGroup:thread.uniqueId];
            if (firstUnseenInteraction) {
                result.firstUnseenInteractionTimestamp = @(firstUnseenInteraction.timestampForSorting);
            }
        }

        __block TSMessage *firstMessage = nil;
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          OWSAssert([object isKindOfClass:[TSInteraction class]]);

                          if ([object isKindOfClass:[TSIncomingMessage class]] ||
                              [object isKindOfClass:[TSOutgoingMessage class]]) {
                              firstMessage = (TSMessage *)object;
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

            OWSAssert(interactionAfterUnreadIndicator);

            if (result.hasMoreUnseenMessages) {
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
                }

                SignalAccount *signalAccount = contactsManager.signalAccountMap[recipientId];
                if (signalAccount) {
                    // Only create "add to contacts" offers for non-contacts.
                    shouldHaveAddToContactsOffer = NO;
                    // Only create block offers for non-contacts.
                    shouldHaveBlockOffer = NO;
                }
            }
        }

        if (!firstMessage) {
            shouldHaveAddToContactsOffer = NO;
            shouldHaveBlockOffer = NO;
        }

        if (outgoingMessageCount > kMaxBlockOfferOutgoingMessageCount) {
            // If the user has sent more than N messages, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        BOOL hasOutgoingBeforeIncomingInteraction = [firstMessage isKindOfClass:[TSOutgoingMessage class]];
        if (hasOutgoingBeforeIncomingInteraction) {
            // If there is an outgoing message before an incoming message
            // the local user initiated this conversation, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        if (![OWSProfileManager.sharedManager hasLocalProfile] ||
            [OWSProfileManager.sharedManager isThreadInProfileWhitelist:thread]) {
            // Don't show offer if thread is local user hasn't configured their profile.
            // Don't show offer if thread is already in profile whitelist.
            shouldHaveAddToProfileWhitelistOffer = NO;
        }

        // We use these offset to control the ordering of the offers and indicators.
        const int kAddToProfileWhitelistOfferOffset = -4;
        const int kBlockOfferOffset = -3;
        const int kAddToContactsOfferOffset = -2;
        const int kUnreadIndicatorOfferOffset = -1;

        if (existingBlockOffer && !shouldHaveBlockOffer) {
            DDLogInfo(@"%@ Removing block offer: %@ (%llu)",
                self.tag,
                existingBlockOffer.uniqueId,
                existingBlockOffer.timestampForSorting);
            [existingBlockOffer removeWithTransaction:transaction];
        } else if (!existingBlockOffer && shouldHaveBlockOffer) {
            DDLogInfo(@"Creating block offer for unknown contact");

            // We want the block offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t blockOfferTimestamp = (uint64_t)((long long)firstMessage.timestampForSorting + kBlockOfferOffset);
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            TSMessage *offerMessage =
                [OWSUnknownContactBlockOfferMessage unknownContactBlockOfferMessage:blockOfferTimestamp
                                                                             thread:thread
                                                                          contactId:recipientId];
            [offerMessage saveWithTransaction:transaction];

            DDLogInfo(@"%@ Creating block offer: %@ (%llu)",
                self.tag,
                offerMessage.uniqueId,
                offerMessage.timestampForSorting);
        }

        if (existingAddToContactsOffer && !shouldHaveAddToContactsOffer) {
            DDLogInfo(@"%@ Removing 'add to contacts' offer: %@ (%llu)",
                self.tag,
                existingAddToContactsOffer.uniqueId,
                existingAddToContactsOffer.timestampForSorting);
            [existingAddToContactsOffer removeWithTransaction:transaction];
        } else if (!existingAddToContactsOffer && shouldHaveAddToContactsOffer) {

            DDLogInfo(@"%@ Creating 'add to contacts' offer for unknown contact", self.tag);

            // We want the offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t offerTimestamp
                = (uint64_t)((long long)firstMessage.timestampForSorting + kAddToContactsOfferOffset);
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            TSMessage *offerMessage = [OWSAddToContactsOfferMessage addToContactsOfferMessage:offerTimestamp
                                                                                       thread:thread
                                                                                    contactId:recipientId];
            [offerMessage saveWithTransaction:transaction];

            DDLogInfo(@"%@ Creating 'add to contacts' offer: %@ (%llu)",
                self.tag,
                offerMessage.uniqueId,
                offerMessage.timestampForSorting);
        }

        if (existingOWSAddToProfileWhitelistOffer && !shouldHaveAddToProfileWhitelistOffer) {
            DDLogInfo(@"%@ Removing 'add to profile whitelist' offer: %@ (%llu)",
                self.tag,
                existingOWSAddToProfileWhitelistOffer.uniqueId,
                existingOWSAddToProfileWhitelistOffer.timestampForSorting);
            [existingOWSAddToProfileWhitelistOffer removeWithTransaction:transaction];
        } else if (!existingOWSAddToProfileWhitelistOffer && shouldHaveAddToProfileWhitelistOffer) {

            DDLogInfo(@"%@ Creating 'add to profile whitelist' offer", self.tag);

            // We want the offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t offerTimestamp
                = (uint64_t)((long long)firstMessage.timestampForSorting + kAddToProfileWhitelistOfferOffset);

            TSMessage *offerMessage =
                [OWSAddToProfileWhitelistOfferMessage addToProfileWhitelistOfferMessage:offerTimestamp thread:thread];
            [offerMessage saveWithTransaction:transaction];

            DDLogInfo(@"%@ Creating 'add to profile whitelist' offer: %@ (%llu)",
                self.tag,
                offerMessage.uniqueId,
                offerMessage.timestampForSorting);
        }

        BOOL shouldHaveUnreadIndicator
            = (interactionAfterUnreadIndicator && !hideUnreadMessagesIndicator && threadMessageCount > 1);
        if (!shouldHaveUnreadIndicator) {
            if (existingUnreadIndicator) {
                DDLogInfo(@"%@ Removing obsolete TSUnreadIndicatorInteraction: %@",
                    self.tag,
                    existingUnreadIndicator.uniqueId);
                [existingUnreadIndicator removeWithTransaction:transaction];
            }
        } else {
            // We want the unread indicator to appear just before the first unread incoming
            // message in the conversation timeline...
            //
            // ...unless we have a fixed timestamp for the unread indicator.
            uint64_t indicatorTimestamp = (uint64_t)(
                (long long)interactionAfterUnreadIndicator.timestampForSorting + kUnreadIndicatorOfferOffset);

            if (indicatorTimestamp && existingUnreadIndicator.timestampForSorting == indicatorTimestamp) {
                // Keep the existing indicator; it is in the correct position.
            } else {
                if (existingUnreadIndicator) {
                    DDLogInfo(@"%@ Removing TSUnreadIndicatorInteraction due to changed timestamp: %@",
                        self.tag,
                        existingUnreadIndicator.uniqueId);
                    [existingUnreadIndicator removeWithTransaction:transaction];
                }

                TSUnreadIndicatorInteraction *indicator =
                    [[TSUnreadIndicatorInteraction alloc] initWithTimestamp:indicatorTimestamp
                                                                     thread:thread
                                                      hasMoreUnseenMessages:result.hasMoreUnseenMessages
                                       missingUnseenSafetyNumberChangeCount:missingUnseenSafetyNumberChangeCount];
                [indicator saveWithTransaction:transaction];

                DDLogInfo(@"%@ Creating TSUnreadIndicatorInteraction: %@ (%llu)",
                    self.tag,
                    indicator.uniqueId,
                    indicator.timestampForSorting);
            }
        }
    }];

    return result;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
