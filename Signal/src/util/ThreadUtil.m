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

+ (void)ensureThreadOffersAndIndicators:(TSContactThread *)contactThread
                         storageManager:(TSStorageManager *)storageManager
                        contactsManager:(OWSContactsManager *)contactsManager
                        blockingManager:(OWSBlockingManager *)blockingManager
{
    OWSAssert(contactThread);
    OWSAssert(storageManager);
    OWSAssert(contactsManager);
    OWSAssert(blockingManager);

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxBlockOfferOutgoingMessageCount = 10;

        __block OWSAddToContactsOfferMessage *addToContactsOffer = nil;
        __block OWSUnknownContactBlockOfferMessage *blockOffer = nil;
        __block TSIncomingMessage *firstIncomingMessage = nil;
        __block TSOutgoingMessage *firstOutgoingMessage = nil;
        __block long outgoingMessageCount = 0;

        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:contactThread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {


                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              OWSAssert(!blockOffer);
                              blockOffer = (OWSUnknownContactBlockOfferMessage *)object;
                          } else if ([object isKindOfClass:[OWSAddToContactsOfferMessage class]]) {
                              OWSAssert(!addToContactsOffer);
                              addToContactsOffer = (OWSAddToContactsOfferMessage *)object;
                          } else if ([object isKindOfClass:[TSIncomingMessage class]]) {
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
        if ([[blockingManager blockedPhoneNumbers] containsObject:contactThread.contactIdentifier]) {
            // Only create offers for users which are not already blocked.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers for users which are not already blocked.
            shouldHaveBlockOffer = NO;
        }

        SignalAccount *signalAccount = contactsManager.signalAccountMap[contactThread.contactIdentifier];
        if (signalAccount) {
            // Only create offers for non-contacts.
            shouldHaveAddToContactsOffer = NO;
            // Only create block offers for non-contacts.
            shouldHaveBlockOffer = NO;
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
        // TODO:
        //        const int kUnseenIndicatorOfferOffset = -1;

        if (blockOffer && !shouldHaveBlockOffer) {
            [blockOffer removeWithTransaction:transaction];
        } else if (!blockOffer && shouldHaveBlockOffer) {
            DDLogInfo(@"Creating block offer for unknown contact");

            // We want the block offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t blockOfferTimestamp = (uint64_t)((long long)firstMessage.timestamp + kBlockOfferOffset);

            TSMessage *offerMessage =
                [OWSUnknownContactBlockOfferMessage unknownContactBlockOfferMessage:blockOfferTimestamp
                                                                             thread:contactThread
                                                                          contactId:contactThread.contactIdentifier];
            [offerMessage saveWithTransaction:transaction];
        }

        if (addToContactsOffer && !shouldHaveAddToContactsOffer) {
            [addToContactsOffer removeWithTransaction:transaction];
        } else if (!addToContactsOffer && shouldHaveAddToContactsOffer) {

            DDLogInfo(@"Creating 'add to contacts' offer for unknown contact");

            // We want the offer to be the first interaction in their
            // conversation's timeline, so we back-date it to slightly before
            // the first incoming message (which we know is the first message).
            uint64_t offerTimestamp = (uint64_t)((long long)firstMessage.timestamp + kAddToContactsOfferOffset);

            TSMessage *offerMessage =
                [OWSAddToContactsOfferMessage addToContactsOfferMessage:offerTimestamp
                                                                 thread:contactThread
                                                              contactId:contactThread.contactIdentifier];
            [offerMessage saveWithTransaction:transaction];
        }
    }];
}

+ (void)createUnreadMessagesIndicatorIfNecessary:(TSThread *)thread storageManager:(TSStorageManager *)storageManager
{
    OWSAssert(thread);
    OWSAssert(storageManager);

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

        NSMutableArray *indicators = [NSMutableArray new];
        __block TSMessage *firstUnreadMessage = nil;
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                              [indicators addObject:object];
                          } else if ([object isKindOfClass:[TSIncomingMessage class]]) {
                              TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                              if (!incomingMessage.wasRead) {
                                  if (!firstUnreadMessage) {
                                      firstUnreadMessage = incomingMessage;
                                  } else {
                                      OWSAssert([[firstUnreadMessage receiptDateForSorting]
                                                    compare:[incomingMessage receiptDateForSorting]]
                                          == NSOrderedAscending);
                                  }
                              }
                          }
                      }];

        for (TSUnreadIndicatorInteraction *indicator in indicators) {
            [indicator removeWithTransaction:transaction];
        }

        BOOL shouldHaveIndicator = firstUnreadMessage != nil;
        if (!shouldHaveIndicator) {
            return;
        }

        DDLogInfo(@"%@ Creating TSUnreadIndicatorInteraction", self.tag);

        // We want the block offer to appear just before the first unread incoming
        // message in the conversation timeline.
        uint64_t indicatorTimestamp = firstUnreadMessage.timestamp - 1;

        TSUnreadIndicatorInteraction *indicator =
            [[TSUnreadIndicatorInteraction alloc] initWithTimestamp:indicatorTimestamp thread:thread];
        [indicator saveWithTransaction:transaction];
    }];
}

+ (void)clearUnreadMessagesIndicator:(TSThread *)thread storageManager:(TSStorageManager *)storageManager
{
    OWSAssert(thread);
    OWSAssert(storageManager);

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

        NSMutableArray *indicators = [NSMutableArray new];
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
                              [indicators addObject:object];
                          }
                      }];

        for (TSUnreadIndicatorInteraction *indicator in indicators) {
            [indicator removeWithTransaction:transaction];
        }
    }];
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
