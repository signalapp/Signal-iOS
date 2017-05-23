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
                                 fixedUnreadIndicatorTimestamp:(NSNumber *_Nullable)fixedUnreadIndicatorTimestamp
{
    OWSAssert(thread);
    OWSAssert(storageManager);
    OWSAssert(contactsManager);
    OWSAssert(blockingManager);

    ThreadOffersAndIndicators *result = [ThreadOffersAndIndicators new];

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxBlockOfferOutgoingMessageCount = 10;

        __block OWSAddToContactsOfferMessage *existingAddToContactsOffer = nil;
        __block OWSUnknownContactBlockOfferMessage *existingBlockOffer = nil;
        __block TSUnreadIndicatorInteraction *existingUnreadIndicator = nil;
        __block TSIncomingMessage *firstIncomingMessage = nil;
        __block TSOutgoingMessage *firstOutgoingMessage = nil;
        __block TSIncomingMessage *firstUnreadMessage = nil;
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
        [[transaction ext:TSUnreadDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if (![object isKindOfClass:[TSIncomingMessage class]]) {
                              DDLogError(@"Unexpected unread message type: %@", [object class]);
                              OWSAssert(0);
                              return;
                          }
                          TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                          if (incomingMessage.wasRead) {
                              DDLogError(@"Unexpectedly read unread message");
                              OWSAssert(0);
                              return;
                          }
                          firstUnreadMessage = incomingMessage;
                          *stop = YES;
                      }];
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[TSIncomingMessage class]]) {
                              TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                              if (!firstIncomingMessage) {
                                  firstIncomingMessage = incomingMessage;
                              } else {
                                  OWSAssert([[firstIncomingMessage receiptDateForSorting]
                                                compare:[incomingMessage receiptDateForSorting]]
                                      == NSOrderedAscending);
                              }
                          } else if ([object isKindOfClass:[TSOutgoingMessage class]]) {
                              TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)object;
                              if (!firstOutgoingMessage) {
                                  firstOutgoingMessage = outgoingMessage;
                              } else {
                                  OWSAssert([[firstOutgoingMessage receiptDateForSorting]
                                                compare:[outgoingMessage receiptDateForSorting]]
                                      == NSOrderedAscending);
                              }
                              outgoingMessageCount++;
                              if (outgoingMessageCount >= kMaxBlockOfferOutgoingMessageCount) {
                                  *stop = YES;
                              }
                          }
                      }];

        TSMessage *firstMessage = firstIncomingMessage;
        if (!firstMessage
            || (firstOutgoingMessage &&
                   [[firstOutgoingMessage receiptDateForSorting] compare:[firstMessage receiptDateForSorting]]
                       == NSOrderedAscending)) {
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
                   [[firstOutgoingMessage receiptDateForSorting] compare:[firstIncomingMessage receiptDateForSorting]]
                       == NSOrderedAscending));
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
            [existingBlockOffer removeWithTransaction:transaction];
        } else if (!existingBlockOffer && shouldHaveBlockOffer) {
            DDLogInfo(@"Creating block offer for unknown contact");

            // We want the block offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t blockOfferTimestamp = (uint64_t)((long long)firstMessage.timestamp + kBlockOfferOffset);
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            TSMessage *offerMessage =
                [OWSUnknownContactBlockOfferMessage unknownContactBlockOfferMessage:blockOfferTimestamp
                                                                             thread:thread
                                                                          contactId:recipientId];
            [offerMessage saveWithTransaction:transaction];
        }

        if (existingAddToContactsOffer && !shouldHaveAddToContactsOffer) {
            [existingAddToContactsOffer removeWithTransaction:transaction];
        } else if (!existingAddToContactsOffer && shouldHaveAddToContactsOffer) {

            DDLogInfo(@"Creating 'add to contacts' offer for unknown contact");

            // We want the offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t offerTimestamp = (uint64_t)((long long)firstMessage.timestamp + kAddToContactsOfferOffset);
            NSString *recipientId = ((TSContactThread *)thread).contactIdentifier;

            TSMessage *offerMessage = [OWSAddToContactsOfferMessage addToContactsOfferMessage:offerTimestamp
                                                                                       thread:thread
                                                                                    contactId:recipientId];
            [offerMessage saveWithTransaction:transaction];
        }

        BOOL shouldHaveUnreadIndicator
            = ((firstUnreadMessage != nil || fixedUnreadIndicatorTimestamp != nil) && !hideUnreadMessagesIndicator);
        if (!shouldHaveUnreadIndicator) {
            if (existingUnreadIndicator) {
                [existingUnreadIndicator removeWithTransaction:transaction];
            }
        } else {
            // We want the block offer to appear just before the first unread incoming
            // message in the conversation timeline...
            //
            // ...unless we have a fixed timestamp for the unread indicator.
            uint64_t indicatorTimestamp = (uint64_t)(fixedUnreadIndicatorTimestamp
                    ? [fixedUnreadIndicatorTimestamp longLongValue]
                    : ((long long)firstUnreadMessage.timestamp + kUnreadIndicatorOfferOffset));

            if (indicatorTimestamp && existingUnreadIndicator.timestamp == indicatorTimestamp) {
                // Keep the existing indicator; it is in the correct position.

                result.unreadIndicator = existingUnreadIndicator;
            } else {
                if (existingUnreadIndicator) {
                    [existingUnreadIndicator removeWithTransaction:transaction];
                }

                DDLogInfo(@"%@ Creating TSUnreadIndicatorInteraction", self.tag);

                TSUnreadIndicatorInteraction *indicator =
                    [[TSUnreadIndicatorInteraction alloc] initWithTimestamp:indicatorTimestamp thread:thread];
                [indicator saveWithTransaction:transaction];

                result.unreadIndicator = indicator;
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
