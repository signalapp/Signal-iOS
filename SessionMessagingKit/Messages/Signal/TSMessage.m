//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import "TSContactThread.h"
#import <SignalCoreKit/NSString+OWS.h>

NS_ASSUME_NONNULL_BEGIN

static const NSUInteger OWSMessageSchemaVersion = 4;
const NSUInteger kOversizeTextMessageSizeThreshold = 2 * 1024;

#pragma mark -

@interface TSMessage ()

@property (nonatomic, nullable) NSString *body;
@property (nonatomic) uint32_t expiresInSeconds;
@property (nonatomic) uint64_t expireStartedAt;

/**
 * The version of the model class's schema last used to serialize this model. Use this to manage data migrations during
 * object de/serialization.
 *
 * e.g.
 *
 *    - (id)initWithCoder:(NSCoder *)coder
 *    {
 *      self = [super initWithCoder:coder];
 *      if (!self) { return self; }
 *      if (_schemaVersion < 2) {
 *        _newName = [coder decodeObjectForKey:@"oldName"]
 *      }
 *      ...
 *      _schemaVersion = 2;
 *    }
 */
@property (nonatomic, readonly) NSUInteger schemaVersion;

@end

#pragma mark -

@implementation TSMessage

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                             linkPreview:(nullable OWSLinkPreview *)linkPreview
                 openGroupInvitationName:(nullable NSString *)openGroupInvitationName
                  openGroupInvitationURL:(nullable NSString *)openGroupInvitationURL
                              serverHash:(nullable NSString *)serverHash
{
    self = [super initInteractionWithTimestamp:timestamp inThread:thread];

    if (!self) {
        return self;
    }

    _schemaVersion = OWSMessageSchemaVersion;

    _body = body;
    _attachmentIds = attachmentIds ? [attachmentIds mutableCopy] : [NSMutableArray new];
    _expiresInSeconds = expiresInSeconds;
    _expireStartedAt = expireStartedAt;
    [self updateExpiresAt];
    _quotedMessage = quotedMessage;
    _linkPreview = linkPreview;
    _openGroupServerMessageID = 0;
    _openGroupInvitationName = openGroupInvitationName;
    _openGroupInvitationURL = openGroupInvitationURL;
    _serverHash = serverHash;
    _isDeleted = false;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_schemaVersion < 2) {
        // renamed _attachments to _attachmentIds
        if (!_attachmentIds) {
            _attachmentIds = [coder decodeObjectForKey:@"attachments"];
        }
    }

    if (_schemaVersion < 3) {
        _expiresInSeconds = 0;
        _expireStartedAt = 0;
        _expiresAt = 0;
    }

    if (_schemaVersion < 4) {
        // Wipe out the body field on these legacy attachment messages.
        //
        // Explantion: Historically, a message sent from iOS could be an attachment XOR a text message,
        // but now we support sending an attachment+caption as a single message.
        //
        // Other clients have supported sending attachment+caption in a single message for a long time.
        // So the way we used to handle receiving them was to make it look like they'd sent two messages:
        // first the attachment+caption (we'd ignore this caption when rendering), followed by a separate
        // message with just the caption (which we'd render as a simple independent text message), for
        // which we'd offset the timestamp by a little bit to get the desired ordering.
        //
        // Now that we can properly render an attachment+caption message together, these legacy "dummy" text
        // messages are not only unnecessary, but worse, would be rendered redundantly. For safety, rather
        // than building the logic to try to find and delete the redundant "dummy" text messages which users
        // have been seeing and interacting with, we delete the body field from the attachment message,
        // which iOS users have never seen directly.
        if (_attachmentIds.count > 0) {
            _body = nil;
        }
    }

    if (!_attachmentIds) {
        _attachmentIds = [NSMutableArray new];
    }

    _schemaVersion = OWSMessageSchemaVersion;

    return self;
}

- (void)setExpiresInSeconds:(uint32_t)expiresInSeconds
{
    uint32_t maxExpirationDuration = [OWSDisappearingMessagesConfiguration maxDurationSeconds];

    _expiresInSeconds = MIN(expiresInSeconds, maxExpirationDuration);
    [self updateExpiresAt];
}

- (void)setExpireStartedAt:(uint64_t)expireStartedAt
{
    if (_expireStartedAt != 0 && _expireStartedAt < expireStartedAt) {
        return;
    }

    uint64_t now = [NSDate ows_millisecondTimeStamp];

    _expireStartedAt = MIN(now, expireStartedAt);
    [self updateExpiresAt];
}

- (BOOL)shouldStartExpireTimerWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return self.isExpiringMessage;
}

// TODO a downloaded media doesn't start counting until download is complete.
- (void)updateExpiresAt
{
    if (_expiresInSeconds > 0 && _expireStartedAt > 0) {
        _expiresAt = _expireStartedAt + _expiresInSeconds * 1000;
    } else {
        _expiresAt = 0;
    }
}

- (BOOL)hasAttachments
{
    return self.attachmentIds ? (self.attachmentIds.count > 0) : NO;
}

- (NSArray<NSString *> *)allAttachmentIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    if (self.attachmentIds.count > 0) {
        [result addObjectsFromArray:self.attachmentIds];
    }

    if (self.quotedMessage) {
        [result addObjectsFromArray:self.quotedMessage.thumbnailAttachmentStreamIds];
    }

    if (self.linkPreview.imageAttachmentId) {
        [result addObject:self.linkPreview.imageAttachmentId];
    }

    return [result copy];
}

- (NSArray<TSAttachment *> *)attachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<TSAttachment *> *attachments = [NSMutableArray new];
    for (NSString *attachmentId in self.attachmentIds) {
        TSAttachment *_Nullable attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if (attachment) {
            [attachments addObject:attachment];
        }
    }
    return [attachments copy];
}

- (NSArray<TSAttachment *> *)attachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                            contentType:(NSString *)contentType
{
    NSArray<TSAttachment *> *attachments = [self attachmentsWithTransaction:transaction];
    return [attachments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TSAttachment *evaluatedObject,
                                                        NSDictionary<NSString *, id> *_Nullable bindings) {
        return [evaluatedObject.contentType isEqualToString:contentType];
    }]];
}

- (NSArray<TSAttachment *> *)attachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                      exceptContentType:(NSString *)contentType
{
    NSArray<TSAttachment *> *attachments = [self attachmentsWithTransaction:transaction];
    return [attachments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TSAttachment *evaluatedObject,
                                                        NSDictionary<NSString *, id> *_Nullable bindings) {
        return ![evaluatedObject.contentType isEqualToString:contentType];
    }]];
}

- (void)removeAttachment:(TSAttachment *)attachment transaction:(YapDatabaseReadWriteTransaction *)transaction;
{
    [attachment removeWithTransaction:transaction];

    [self.attachmentIds removeObject:attachment.uniqueId];

    [self saveWithTransaction:transaction];
}

- (void)addAttachmentWithID:(NSString *)attachmentID in:(YapDatabaseReadWriteTransaction *)transaction {
    if (!self.attachmentIds) { return; }
    [self.attachmentIds addObject:attachmentID];
    [self saveWithTransaction:transaction];
}

- (NSString *)debugDescription
{
    if ([self hasAttachments] && self.body.length > 0) {
        NSString *attachmentId = self.attachmentIds[0];
        return [NSString
            stringWithFormat:@"Media Message with attachmentId: %@ and caption: '%@'", attachmentId, self.body];
    } else if ([self hasAttachments]) {
        NSString *attachmentId = self.attachmentIds[0];
        return [NSString stringWithFormat:@"Media Message with attachmentId: %@", attachmentId];
    } else {
        return [NSString stringWithFormat:@"%@ with body: %@", [self class], self.body];
    }
}

- (nullable TSAttachment *)oversizeTextAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [self attachmentsWithTransaction:transaction contentType:OWSMimeTypeOversizeTextMessage].firstObject;
}

- (NSArray<TSAttachment *> *)mediaAttachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [self attachmentsWithTransaction:transaction exceptContentType:OWSMimeTypeOversizeTextMessage];
}

- (nullable NSString *)oversizeTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSAttachment *_Nullable attachment = [self oversizeTextAttachmentWithTransaction:transaction];
    if (!attachment) {
        return nil;
    }

    if (![attachment isKindOfClass:TSAttachmentStream.class]) {
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

    NSData *_Nullable data = [NSData dataWithContentsOfFile:attachmentStream.originalFilePath];
    if (!data) {
        return nil;
    }
    NSString *_Nullable text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        return nil;
    }
    return text.filterStringForDisplay;
}

- (nullable NSString *)bodyTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *_Nullable oversizeText = [self oversizeTextWithTransaction:transaction];
    if (oversizeText) {
        return oversizeText;
    }

    if (self.body.length > 0) {
        return self.body.filterStringForDisplay;
    }

    return nil;
}

// TODO: This method contains view-specific logic and probably belongs in NotificationsManager, not in SSK.
- (NSString *)previewTextWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *_Nullable bodyDescription = nil;
    if (self.body.length > 0) {
        bodyDescription = self.body;
    }

    if (bodyDescription == nil) {
        TSAttachment *_Nullable oversizeTextAttachment = [self oversizeTextAttachmentWithTransaction:transaction];
        if ([oversizeTextAttachment isKindOfClass:[TSAttachmentStream class]]) {
            TSAttachmentStream *oversizeTextAttachmentStream = (TSAttachmentStream *)oversizeTextAttachment;
            NSData *_Nullable data = [NSData dataWithContentsOfFile:oversizeTextAttachmentStream.originalFilePath];
            if (data) {
                NSString *_Nullable text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (text) {
                    bodyDescription = text.filterStringForDisplay;
                }
            }
        }
    }

    NSString *_Nullable attachmentDescription = nil;
    TSAttachment *_Nullable mediaAttachment = [self mediaAttachmentsWithTransaction:transaction].firstObject;
    if (mediaAttachment != nil) {
        attachmentDescription = mediaAttachment.description;
    }

    if (attachmentDescription.length > 0 && bodyDescription.length > 0) {
        // Attachment with caption.
        if ([CurrentAppContext() isRTL]) {
            return [[bodyDescription stringByAppendingString:@": "] stringByAppendingString:attachmentDescription];
        } else {
            return [[attachmentDescription stringByAppendingString:@": "] stringByAppendingString:bodyDescription];
        }
    } else if (bodyDescription.length > 0) {
        return bodyDescription;
    } else if (attachmentDescription.length > 0) {
        return attachmentDescription;
    } else if (self.openGroupInvitationName != nil) {
        return @"😎 Open group invitation";
    } else {
        // TODO: We should do better here.
        return @"";
    }
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];

    for (NSString *attachmentId in self.allAttachmentIds) {
        // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
        TSAttachment *_Nullable attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if (!attachment) {
            continue;
        }
        [attachment removeWithTransaction:transaction];
    };
}

- (BOOL)isExpiringMessage
{
    return self.expiresInSeconds > 0;
}

- (uint64_t)timestampForLegacySorting
{
    if ([self shouldUseReceiptDateForSorting] && self.receivedAtTimestamp > 0) {
        return self.receivedAtTimestamp;
    } else {
        return self.timestamp;
    }
}

- (BOOL)shouldUseReceiptDateForSorting
{
    return YES;
}

- (nullable NSString *)body
{
    return _body.filterStringForDisplay;
}

- (void)setQuotedMessageThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    [self.quotedMessage setThumbnailAttachmentStream:attachmentStream];
}

- (BOOL)isOpenGroupMessage
{
    return (self.openGroupServerMessageID != 0);
}

#pragma mark - Update With... Methods

- (void)updateWithExpireStartedAt:(uint64_t)expireStartedAt transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSMessage *message) {
                                 [message setExpireStartedAt:expireStartedAt];
                             }];
}

- (void)updateWithLinkPreview:(OWSLinkPreview *)linkPreview transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSMessage *message) {
                                 [message setLinkPreview:linkPreview];
                             }];
}

- (void)updateForDeletionWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSMessage *message) {
                                [message setBody:nil];
                                [message setServerHash:nil];
                                for (NSString *attachmentId in message.attachmentIds) {
                                    TSAttachment *_Nullable attachment =
                                        [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
                                    if (attachment) {
                                        [attachment removeWithTransaction:transaction];
                                    }
                                }
                                [message setIsDeleted:true];
                             }];
}

@end

NS_ASSUME_NONNULL_END
