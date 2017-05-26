//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "TSUnreadIndicatorInteraction.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ThreadOffersAndIndicators

@end

#pragma mark -

@implementation ThreadUtil

+ (void)sendMessageWithText:(NSString *)text inThread:(TSThread *)thread messageSender:(OWSMessageSender *)messageSender
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
    [messageSender sendMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent message.", self.tag);
        }
        failure:^(NSError *error) {
            DDLogWarn(@"%@ Failed to deliver message with error: %@", self.tag, error);
        }];
}


+ (void)sendMessageWithAttachment:(SignalAttachment *)attachment
                         inThread:(TSThread *)thread
                    messageSender:(OWSMessageSender *)messageSender
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(attachment);
    OWSAssert(![attachment hasError]);
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
}

+ (ThreadOffersAndIndicators *)ensureThreadOffersAndIndicators:(TSThread *)thread
                                                storageManager:(TSStorageManager *)storageManager
                                               contactsManager:(OWSContactsManager *)contactsManager
                                               blockingManager:(OWSBlockingManager *)blockingManager
                                   hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                               firstUnseenInteractionTimestamp:
                                   (nullable NSNumber *)firstUnseenInteractionTimestampParameter
                                                  maxRangeSize:(int)maxRangeSize
{
    OWSAssert(thread);
    OWSAssert(storageManager);
    OWSAssert(contactsManager);
    OWSAssert(blockingManager);
    OWSAssert(maxRangeSize > 0);

    ThreadOffersAndIndicators *result = [ThreadOffersAndIndicators new];

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxBlockOfferOutgoingMessageCount = 10;

        __block OWSAddToContactsOfferMessage *existingAddToContactsOffer = nil;
        __block OWSUnknownContactBlockOfferMessage *existingBlockOffer = nil;
        __block TSUnreadIndicatorInteraction *existingUnreadIndicator = nil;
        __block TSIncomingMessage *firstIncomingMessage = nil;
        __block TSOutgoingMessage *firstOutgoingMessage = nil;
        __block long outgoingMessageCount = 0;

        // We use different views for performance reasons.
        [[transaction ext:TSDynamicMessagesDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              OWSAssert(!existingBlockOffer);
                              existingBlockOffer = (OWSUnknownContactBlockOfferMessage *)object;
                          } else if ([object isKindOfClass:[OWSAddToContactsOfferMessage class]]) {
                              OWSAssert(!existingAddToContactsOffer);
                              existingAddToContactsOffer = (OWSAddToContactsOfferMessage *)object;
                          } else if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                              OWSAssert(!existingUnreadIndicator);
                              existingUnreadIndicator = (TSUnreadIndicatorInteraction *)object;
                          } else {
                              DDLogError(@"Unexpected dynamic interaction type: %@", [object class]);
                              OWSAssert(0);
                          }
                      }];

        // We use different views for performance reasons.
        NSMutableArray<TSInvalidIdentityKeyErrorMessage *> *safetyNumberChanges = [NSMutableArray new];
        [[transaction ext:TSSafetyNumberChangeDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                              [safetyNumberChanges addObject:object];
                          } else {
                              DDLogError(@"Unexpected interaction type: %@", [object class]);
                              OWSAssert(0);
                          }
                      }];

        // IFF this variable is non-null, there are unseen messages in the thread.
        __block NSNumber *firstUnseenInteractionTimestamp;
        if (firstUnseenInteractionTimestampParameter) {
            firstUnseenInteractionTimestamp = firstUnseenInteractionTimestampParameter;
        } else {
            [[transaction ext:TSUnseenDatabaseViewExtensionName]
                enumerateRowsInGroup:thread.uniqueId
                          usingBlock:^(NSString *collection,
                              NSString *key,
                              id object,
                              id metadata,
                              NSUInteger index,
                              BOOL *stop) {

                              if (![object isKindOfClass:[TSInteraction class]]) {
                                  DDLogError(@"Unexpected unread message type: %@", [object class]);
                                  OWSAssert(0);
                                  return;
                              }
                              OWSAssert(!((id<OWSReadTracking>)object).wasRead);
                              TSInteraction *interaction = (TSInteraction *)object;
                              firstUnseenInteractionTimestamp = @(interaction.timestampForSorting);
                              *stop = YES;
                          }];
        }

        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[TSIncomingMessage class]]) {
                              TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                              if (!firstIncomingMessage) {
                                  firstIncomingMessage = incomingMessage;
                              } else {
                                  OWSAssert(
                                      [firstIncomingMessage compareForSorting:incomingMessage] == NSOrderedAscending);
                              }
                          } else if ([object isKindOfClass:[TSOutgoingMessage class]]) {
                              TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)object;
                              if (!firstOutgoingMessage) {
                                  firstOutgoingMessage = outgoingMessage;
                              } else {
                                  OWSAssert(
                                      [firstOutgoingMessage compareForSorting:outgoingMessage] == NSOrderedAscending);
                              }
                              outgoingMessageCount++;
                              if (outgoingMessageCount >= kMaxBlockOfferOutgoingMessageCount) {
                                  *stop = YES;
                              }
                          }
                      }];


        // Enumerate in reverse to count the number of unseen messages
        // after the unseen messages indicator.
        __block long visibleUnseenMessageCount = 0;
        __block BOOL hasMoreUnseenMessages = NO;
        __block TSInteraction *interactionAfterUnreadIndicator = nil;
        NSUInteger missingUnseenSafetyNumberChangeCount = 0;
        if (firstUnseenInteractionTimestamp) {
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
                                  OWSFail(@"Expected a TSInteraction");
                                  return;
                              }

                              if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                                  // Ignore existing unread indicator, if any.
                                  return;
                              }

                              TSInteraction *interaction = (TSInteraction *)object;

                              if (interaction.timestampForSorting
                                  < firstUnseenInteractionTimestamp.unsignedLongLongValue) {
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

            OWSAssert(interactionAfterUnreadIndicator);

            if (hasMoreUnseenMessages) {
                NSMutableSet<NSData *> *missingUnseenSafetyNumberChanges = [NSMutableSet set];
                for (TSInvalidIdentityKeyErrorMessage *safetyNumberChange in safetyNumberChanges) {
                    BOOL isUnseen = safetyNumberChange.timestampForSorting
                        >= firstUnseenInteractionTimestamp.unsignedLongLongValue;
                    if (!isUnseen) {
                        continue;
                    }
                    BOOL isMissing
                        = safetyNumberChange.timestampForSorting < interactionAfterUnreadIndicator.timestampForSorting;
                    if (!isMissing) {
                        continue;
                    }
                    [missingUnseenSafetyNumberChanges addObject:safetyNumberChange.newIdentityKey];
                }

                missingUnseenSafetyNumberChangeCount = missingUnseenSafetyNumberChanges.count;
            }
        }
        result.firstUnseenInteractionTimestamp = firstUnseenInteractionTimestamp;
        if (hasMoreUnseenMessages) {
            // The unread indicator is _before_ the last visible unseen message.
            result.unreadIndicatorPosition = @(visibleUnseenMessageCount);
        }

        TSMessage *firstMessage = firstIncomingMessage;
        if (!firstMessage
            || (firstOutgoingMessage && [firstOutgoingMessage compareForSorting:firstMessage] == NSOrderedAscending)) {
            firstMessage = firstOutgoingMessage;
        }

        BOOL shouldHaveBlockOffer = YES;
        BOOL shouldHaveAddToContactsOffer = YES;

        BOOL isContactThread = [thread isKindOfClass:[TSContactThread class]];
        if (!isContactThread) {
            // Only create "add to contacts" offers in 1:1 conversations.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers in 1:1 conversations.
            shouldHaveBlockOffer = NO;
        } else {
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

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

        if (!firstMessage) {
            shouldHaveAddToContactsOffer = NO;
            shouldHaveBlockOffer = NO;
        }

        if (outgoingMessageCount > kMaxBlockOfferOutgoingMessageCount) {
            // If the user has sent more than N messages, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        BOOL hasOutgoingBeforeIncomingInteraction = (firstOutgoingMessage
            && (!firstIncomingMessage ||
                   [firstOutgoingMessage compareForSorting:firstIncomingMessage] == NSOrderedAscending));
        if (hasOutgoingBeforeIncomingInteraction) {
            // If there is an outgoing message before an incoming message
            // the local user initiated this conversation, don't show a block offer.
            shouldHaveBlockOffer = NO;
        }

        // We use these offset to control the ordering of the offers and indicators.
        const int kBlockOfferOffset = -3;
        const int kAddToContactsOfferOffset = -2;
        const int kUnreadIndicatorOfferOffset = -1;

        if (existingBlockOffer && !shouldHaveBlockOffer) {
            DDLogInfo(@"Removing block offer");
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
        }

        if (existingAddToContactsOffer && !shouldHaveAddToContactsOffer) {
            DDLogInfo(@"Removing 'add to contacts' offer");
            [existingAddToContactsOffer removeWithTransaction:transaction];
        } else if (!existingAddToContactsOffer && shouldHaveAddToContactsOffer) {

            DDLogInfo(@"Creating 'add to contacts' offer for unknown contact");

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
        }

        BOOL shouldHaveUnreadIndicator = (interactionAfterUnreadIndicator && !hideUnreadMessagesIndicator);
        if (!shouldHaveUnreadIndicator) {
            if (existingUnreadIndicator) {
                DDLogInfo(@"%@ Removing obsolete TSUnreadIndicatorInteraction: %@",
                    self.tag,
                    existingUnreadIndicator.uniqueId);
                [existingUnreadIndicator removeWithTransaction:transaction];
            }
        } else {
            // We want the block offer to appear just before the first unread incoming
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
                                                      hasMoreUnseenMessages:hasMoreUnseenMessages
                                       missingUnseenSafetyNumberChangeCount:missingUnseenSafetyNumberChangeCount];
                [indicator saveWithTransaction:transaction];

                DDLogInfo(@"%@ Creating TSUnreadIndicatorInteraction: %@", self.tag, indicator.uniqueId);
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
