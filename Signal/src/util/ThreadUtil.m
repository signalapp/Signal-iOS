//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "TSUnreadIndicatorInteraction.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
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

+ (void)createBlockOfferIfNecessary:(TSContactThread *)contactThread
                     storageManager:(TSStorageManager *)storageManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    blockingManager:(OWSBlockingManager *)blockingManager
{
    OWSAssert(contactThread);
    OWSAssert(storageManager);
    OWSAssert(contactsManager);
    OWSAssert(blockingManager);

    if ([[blockingManager blockedPhoneNumbers] containsObject:contactThread.contactIdentifier]) {
        // Only create block offers for users which are not already blocked.
        return;
    }

    SignalAccount *signalAccount = contactsManager.signalAccountMap[contactThread.contactIdentifier];
    if (signalAccount) {
        // Only create block offers for non-contacts.
        return;
    }

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxOutgoingMessageCount = 10;

        __block TSIncomingMessage *firstIncomingMessage = nil;
        __block TSOutgoingMessage *firstOutgoingMessage = nil;
        __block long outgoingMessageCount = 0;
        __block BOOL hasUnknownContactBlockOffer = NO;

        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:contactThread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              hasUnknownContactBlockOffer = YES;
                              // If there already is a block offer, abort.
                              *stop = YES;
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
                              if (outgoingMessageCount > kMaxOutgoingMessageCount) {
                                  // If the user has sent more than N interactions, abort.
                                  *stop = YES;
                              }
                          }
                      }];

        if (!firstIncomingMessage && !firstOutgoingMessage) {
            // If the thread has no interactions, abort.
            return;
        }

        if (outgoingMessageCount > kMaxOutgoingMessageCount) {
            // If the user has sent more than N messages, abort.
            return;
        }

        if (hasUnknownContactBlockOffer) {
            // If there already is a block offer, abort.
            return;
        }

        BOOL hasOutgoingBeforeIncomingInteraction = (firstOutgoingMessage
            && (!firstIncomingMessage ||
                   [[firstOutgoingMessage receiptDateForSorting] compare:[firstIncomingMessage receiptDateForSorting]]
                       == NSOrderedAscending));
        if (hasOutgoingBeforeIncomingInteraction) {
            // If there is an outgoing message before an incoming message
            // the local user initiated this conversation, abort.
            return;
        }

        DDLogInfo(@"Creating block offer for unknown contact");

        // We want the block offer to be the first interaction in their
        // conversation's timeline, so we back-date it to slightly before
        // the first incoming message (which we know is the first message).
        TSIncomingMessage *firstMessage = firstIncomingMessage;
        uint64_t blockOfferTimestamp = firstMessage.timestamp - 1;

        TSErrorMessage *errorMessage =
            [OWSUnknownContactBlockOfferMessage unknownContactBlockOfferMessage:blockOfferTimestamp
                                                                         thread:contactThread
                                                                      contactId:contactThread.contactIdentifier];
        [errorMessage saveWithTransaction:transaction];
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
