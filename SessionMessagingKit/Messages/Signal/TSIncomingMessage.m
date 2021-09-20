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
#import <YapDatabase/YapDatabaseConnection.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSIncomingMessage ()

@property (nonatomic, getter=wasRead) BOOL read;

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
        _authorId = [TSContactThread contactSessionIDFromThreadID:self.uniqueThreadId];
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                         authorId:(NSString *)authorId
                   sourceDeviceId:(uint32_t)sourceDeviceId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                    quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                      linkPreview:(nullable OWSLinkPreview *)linkPreview
                  wasReceivedByUD:(BOOL)wasReceivedByUD
          openGroupInvitationName:(nullable NSString *)openGroupInvitationName
           openGroupInvitationURL:(nullable NSString *)openGroupInvitationURL
                       serverHash:(nullable NSString *)serverHash
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:0
                             quotedMessage:quotedMessage
                               linkPreview:linkPreview
                   openGroupInvitationName:openGroupInvitationName
                    openGroupInvitationURL:openGroupInvitationURL
                                serverHash:serverHash];

    if (!self) {
        return self;
    }

    _authorId = authorId;
    _sourceDeviceId = sourceDeviceId;
    _read = NO;
    _wasReceivedByUD = wasReceivedByUD;
    _notificationIdentifier = nil;

    return self;
}

+ (nullable instancetype)findMessageWithAuthorId:(NSString *)authorId
                                       timestamp:(uint64_t)timestamp
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
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

- (BOOL)isUserMentioned
{
    NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
    return (self.body != nil && [self.body containsString:[NSString stringWithFormat:@"@%@", userPublicKey]]) || (self.quotedMessage != nil && [self.quotedMessage.authorId isEqualToString:userPublicKey]);
}

- (void)setNotificationIdentifier:(NSString * _Nullable)notificationIdentifier transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
    _notificationIdentifier = notificationIdentifier;
    [self saveWithTransaction:transaction];
}

#pragma mark - OWSReadTracking

- (BOOL)shouldAffectUnreadCounts
{
    return YES;
}

- (void)markAsReadNowWithSendReadReceipt:(BOOL)sendReadReceipt
                             transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    [self markAsReadAtTimestamp:[NSDate millisecondTimestamp]
                sendReadReceipt:sendReadReceipt
                    transaction:transaction];
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
              sendReadReceipt:(BOOL)sendReadReceipt
                  transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    if (_read && readTimestamp >= self.expireStartedAt) {
        return;
    }
    BOOL isTrusted = YES;
    TSThread* thread = [self threadWithTransaction:transaction];
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread* contactThread = (TSContactThread*)thread;
        isTrusted = [[LKStorage shared] getContactWithSessionID:[contactThread contactSessionID] using:transaction].isTrusted;
    }
    
    BOOL areAllAttachmentsDownloaded = YES;
    if (isTrusted) {
        for (NSString *attachmentId in self.attachmentIds) {
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            // If the attachment download failed, we can mark this message as read.
            // Otherwise, this message will never be marked as read.
            if ([attachment isKindOfClass:[TSAttachmentPointer class]]
                && ((TSAttachmentPointer *)attachment).state == TSAttachmentPointerStateFailed) {
                continue;
            }
            areAllAttachmentsDownloaded = areAllAttachmentsDownloaded && attachment.isDownloaded;
            if (!areAllAttachmentsDownloaded) break;
        }
    }
    
    if (!areAllAttachmentsDownloaded) {
        return;
    }
    
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
