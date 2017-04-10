//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ThreadUtil.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
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

    TSOutgoingMessage *message;
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];
    if (configuration.isEnabled) {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:thread
                                                   messageBody:text
                                                 attachmentIds:[NSMutableArray new]
                                              expiresInSeconds:configuration.durationSeconds];
    } else {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:thread
                                                   messageBody:text];
    }

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

    TSOutgoingMessage *message;
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:thread.uniqueId];
    if (configuration.isEnabled) {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:thread
                                                   messageBody:nil
                                                 attachmentIds:[NSMutableArray new]
                                              expiresInSeconds:configuration.durationSeconds];
    } else {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:thread
                                                   messageBody:nil
                                                 attachmentIds:[NSMutableArray new]];
    }

    [messageSender sendAttachmentData:attachment.data
        contentType:[attachment mimeType]
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

    Contact *contact = [contactsManager contactForPhoneIdentifier:contactThread.contactIdentifier];
    if (contact) {
        // Only create block offers for non-contacts.
        return;
    }

    [storageManager.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        const int kMaxOutgoingMessageCount = 10;

        __block TSIncomingMessage *firstIncomingMessage = nil;
        __block TSOutgoingMessage *firstOutgoingMessage = nil;
        __block long outgoingMessageCount = 0;
        __block BOOL hasUnknownContactBlockOffer = NO;

        NSMutableArray *blockOffers = [NSMutableArray new];
        [[transaction ext:TSMessageDatabaseViewExtensionName]
            enumerateRowsInGroup:contactThread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          if ([object isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
                              hasUnknownContactBlockOffer = YES;
                              [blockOffers addObject:object];
                          } else if ([object isKindOfClass:[TSIncomingMessage class]]) {
                              TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;
                              if (!firstIncomingMessage ||
                                  [[firstIncomingMessage receiptDateForSorting]
                                      compare:[incomingMessage receiptDateForSorting]]
                                      == NSOrderedDescending) {
                                  firstIncomingMessage = incomingMessage;
                              }
                          } else if ([object isKindOfClass:[TSOutgoingMessage class]]) {
                              TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)object;
                              if (!firstOutgoingMessage ||
                                  [[firstOutgoingMessage receiptDateForSorting]
                                      compare:[outgoingMessage receiptDateForSorting]]
                                      == NSOrderedDescending) {
                                  firstOutgoingMessage = outgoingMessage;
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

        // Create an error message we may or may not user.
        // We create it eagerly to ensure that it's timestamps make it the
        // first message in the thread.
        TSErrorMessage *errorMessage =
            [OWSUnknownContactBlockOfferMessage unknownContactBlockOfferMessage:blockOfferTimestamp
                                                                         thread:contactThread
                                                                      contactId:contactThread.contactIdentifier];
        [errorMessage saveWithTransaction:transaction];
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
