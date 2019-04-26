//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSReadReceiptManager.h"
#import "TSAttachmentPointer.h"
#import "TSContactThread.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSGroupThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSIncomingMessage ()

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, nullable) NSNumber *serverTimestamp;

@end

#pragma mark -

@implementation TSIncomingMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_authorId == nil) {
        OWSAssertDebug([self.uniqueThreadId hasPrefix:TSContactThreadPrefix]);
        _authorId = [TSContactThread contactIdFromThreadId:self.uniqueThreadId];
    }

    return self;
}

- (instancetype)initIncomingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(TSThread *)thread
                                        authorId:(NSString *)authorId
                                  sourceDeviceId:(uint32_t)sourceDeviceId
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                                 serverTimestamp:(nullable NSNumber *)serverTimestamp
                                 wasReceivedByUD:(BOOL)wasReceivedByUD
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:0
                             quotedMessage:quotedMessage
                              contactShare:contactShare
                               linkPreview:linkPreview];

    if (!self) {
        return self;
    }

    _authorId = authorId;
    _sourceDeviceId = sourceDeviceId;
    _read = NO;
    _serverTimestamp = serverTimestamp;
    _wasReceivedByUD = wasReceivedByUD;

    return self;
}

+ (nullable instancetype)findMessageWithAuthorId:(NSString *)authorId
                                       timestamp:(uint64_t)timestamp
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    __block TSIncomingMessage *foundMessage;
    // In theory we could build a new secondaryIndex for (authorId,timestamp), but in practice there should
    // be *very* few (millisecond) timestamps with multiple authors.
    [TSDatabaseSecondaryIndexes
        enumerateMessagesWithTimestamp:timestamp
                             withBlock:^(NSString *collection, NSString *key, BOOL *stop) {
                                 TSInteraction *interaction =
                                     [TSInteraction fetchObjectWithUniqueID:key transaction:transaction];
                                 if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
                                     TSIncomingMessage *message = (TSIncomingMessage *)interaction;

                                     OWSAssertDebug(message.authorId > 0);

                                     if ([message.authorId isEqualToString:authorId]) {
                                         foundMessage = message;
                                     }
                                 }
                             }
                      usingTransaction:transaction];

    return foundMessage;
}


- (OWSInteractionType)interactionType
{
    return OWSInteractionType_IncomingMessage;
}

- (BOOL)shouldStartExpireTimerWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    for (NSString *attachmentId in self.attachmentIds) {
        TSAttachment *_Nullable attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            return NO;
        }
    }
    return self.isExpiringMessage;
}

#pragma mark - OWSReadTracking

- (BOOL)shouldAffectUnreadCounts
{
    return YES;
}

- (void)markAsReadNowWithSendReadReceipt:(BOOL)sendReadReceipt
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    [self markAsReadAtTimestamp:[NSDate ows_millisecondTimeStamp]
                sendReadReceipt:sendReadReceipt
                    transaction:transaction];
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
              sendReadReceipt:(BOOL)sendReadReceipt
                  transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    OWSAssertDebug(transaction);

    if (_read && readTimestamp >= self.expireStartedAt) {
        return;
    }
    
    NSTimeInterval secondsAgoRead = ((NSTimeInterval)[NSDate ows_millisecondTimeStamp] - (NSTimeInterval)readTimestamp) / 1000;
    OWSLogDebug(@"marking uniqueId: %@  which has timestamp: %llu as read: %f seconds ago",
        self.uniqueId,
        self.timestamp,
        secondsAgoRead);
    _read = YES;
    [self saveWithTransaction:transaction];
    
    [transaction addCompletionQueue:nil
                    completionBlock:^{
                        [[NSNotificationCenter defaultCenter]
                         postNotificationNameAsync:kIncomingMessageMarkedAsReadNotification
                         object:self];
                    }];

    [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:self
                                                     expirationStartedAt:readTimestamp
                                                             transaction:transaction];

    if (sendReadReceipt) {
        [OWSReadReceiptManager.sharedManager messageWasReadLocally:self];
    }
}

@end

NS_ASSUME_NONNULL_END
