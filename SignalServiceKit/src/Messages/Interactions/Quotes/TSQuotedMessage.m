//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSQuotedMessage.h"
#import "OWSPaymentMessage.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAttachmentInfo

- (nullable NSString *)attachmentId
{
    return _rawAttachmentId.ows_nilIfEmpty;
}

- (instancetype)initWithoutThumbnailWithContentType:(NSString *)contentType sourceFilename:(NSString *)sourceFilename
{
    self = [super init];
    if (self) {
        _schemaVersion = self.class.currentSchemaVersion;
        _rawAttachmentId = nil;
        _attachmentType = OWSAttachmentInfoReferenceUnset;
        _contentType = contentType;
        _sourceFilename = sourceFilename;
    }
    return self;
}

- (instancetype)initWithOriginalAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssertDebug(attachmentStream.uniqueId);
    OWSAssertDebug(attachmentStream.contentType);

    if ([TSAttachmentStream hasThumbnailForMimeType:attachmentStream.contentType]) {
        return [self initWithAttachmentId:attachmentStream.uniqueId
                                   ofType:OWSAttachmentInfoReferenceOriginalForSend
                              contentType:attachmentStream.contentType
                           sourceFilename:attachmentStream.sourceFilename];
    } else {
        return [self initWithoutThumbnailWithContentType:attachmentStream.contentType
                                          sourceFilename:attachmentStream.sourceFilename];
    }
}

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                              ofType:(OWSAttachmentInfoReference)attachmentType
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
{
    self = [super init];
    if (self) {
        _schemaVersion = self.class.currentSchemaVersion;
        _rawAttachmentId = attachmentId;
        _attachmentType = attachmentType;
        _contentType = contentType;
        _sourceFilename = sourceFilename;
    }
    return self;
}

+ (NSUInteger)currentSchemaVersion
{
    return 1;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_schemaVersion == 0) {
        NSString *_Nullable oldStreamId = [coder decodeObjectOfClass:[NSString class]
                                                              forKey:@"thumbnailAttachmentStreamId"];
        NSString *_Nullable oldPointerId = [coder decodeObjectOfClass:[NSString class]
                                                               forKey:@"thumbnailAttachmentPointerId"];
        NSString *_Nullable oldSourceAttachmentId = [coder decodeObjectOfClass:[NSString class] forKey:@"attachmentId"];

        // Before, we maintained each of these IDs in parallel, though in practice only one in use at a time.
        // Migration codifies this behavior.
        if (oldStreamId && [oldPointerId isEqualToString:oldStreamId]) {
            _attachmentType = OWSAttachmentInfoReferenceThumbnail;
            _rawAttachmentId = oldStreamId;
        } else if (oldPointerId) {
            _attachmentType = OWSAttachmentInfoReferenceUntrustedPointer;
            _rawAttachmentId = oldPointerId;
        } else if (oldStreamId) {
            _attachmentType = OWSAttachmentInfoReferenceThumbnail;
            _rawAttachmentId = oldStreamId;
        } else if (oldSourceAttachmentId) {
            _attachmentType = OWSAttachmentInfoReferenceOriginalForSend;
            _rawAttachmentId = oldSourceAttachmentId;
        } else {
            _attachmentType = OWSAttachmentInfoReferenceUnset;
            _rawAttachmentId = nil;
        }
    }
    _schemaVersion = self.class.currentSchemaVersion;
    return self;
}

@end

@interface TSQuotedMessage ()
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, nullable) OWSAttachmentInfo *quotedAttachment;
@end

@implementation TSQuotedMessage

// Private
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
     receivedQuotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = bodySource;
    _quotedAttachment = attachmentInfo;
    _isGiftBadge = isGiftBadge;

    return self;
}

// Public
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable TSAttachmentStream *)attachment
                      isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    if (timestamp) {
        OWSAssertDebug(timestamp > 0);
        _timestamp = [timestamp unsignedLongLongValue];
    } else {
        _timestamp = 0;
    }
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = TSQuotedMessageContentSourceLocal;
    _quotedAttachment = attachment ? [[OWSAttachmentInfo alloc] initWithOriginalAttachmentStream:attachment] : nil;
    _isGiftBadge = isGiftBadge;

    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_authorAddress == nil) {
        NSString *phoneNumber = [coder decodeObjectForKey:@"authorId"];
        _authorAddress = [SignalServiceAddress legacyAddressWithServiceIdString:nil phoneNumber:phoneNumber];
        OWSAssertDebug(_authorAddress.isValid);
    }

    if (_quotedAttachment == nil) {
        NSSet *expectedClasses = [NSSet setWithArray:@[ [NSArray class], [OWSAttachmentInfo class] ]];
        NSArray *_Nullable attachmentInfos = [coder decodeObjectOfClasses:expectedClasses forKey:@"quotedAttachments"];

        if ([attachmentInfos.firstObject isKindOfClass:[OWSAttachmentInfo class]]) {
            // In practice, we only used the first item of this array
            OWSAssertDebug(attachmentInfos.count <= 1);
            _quotedAttachment = attachmentInfos.firstObject;
        }
    }

    return self;
}

+ (TSQuotedMessage *_Nullable)quotedMessageForDataMessage:(SSKProtoDataMessage *)dataMessage
                                                   thread:(TSThread *)thread
                                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(dataMessage);

    if (!dataMessage.quote) {
        return nil;
    }

    SSKProtoDataMessageQuote *quoteProto = [dataMessage quote];

    if (quoteProto.id == 0) {
        OWSFailDebug(@"quoted message missing id");
        return nil;
    }
    uint64_t timestamp = [quoteProto id];
    if (![SDS fitsInInt64:timestamp]) {
        OWSFailDebug(@"Invalid timestamp");
        return nil;
    }

    AciObjC *quoteAuthor = [[AciObjC alloc] initWithAciString:quoteProto.authorAci];
    if (quoteAuthor == nil) {
        OWSFailDebug(@"quoted message missing author");
        return nil;
    }
    SignalServiceAddress *quoteAuthorAddress = [[SignalServiceAddress alloc] initWithServiceIdObjC:quoteAuthor];

    TSQuotedMessage *_Nullable quotedMessage = nil;
    TSMessage *_Nullable originalMessage = [InteractionFinder findMessageWithTimestamp:timestamp
                                                                              threadId:thread.uniqueId
                                                                                author:quoteAuthorAddress
                                                                           transaction:transaction];
    if (originalMessage) {
        // Prefer to generate the quoted content locally if available.
        quotedMessage = [self localQuotedMessageFromSourceMessage:originalMessage
                                                       quoteProto:quoteProto
                                                 quoteProtoAuthor:quoteAuthor
                                                      transaction:transaction];
    }
    if (!quotedMessage) {
        // If we couldn't generate the quoted content from locally available info, we can generate it from the proto.
        quotedMessage = [self remoteQuotedMessageFromQuoteProto:quoteProto
                                                    quoteAuthor:quoteAuthor
                                                    transaction:transaction];
    }

    OWSAssertDebug(quotedMessage);
    return quotedMessage;
}

+ (instancetype)quotedMessageWithTargetMessageTimestamp:(nullable NSNumber *)timestamp
                                          authorAddress:(SignalServiceAddress *)authorAddress
                                                   body:(NSString *)body
                                             bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                                             bodySource:(TSQuotedMessageContentSource)bodySource
                                            isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(authorAddress.isValid);

    uint64_t rawTimestamp;
    if (timestamp) {
        OWSAssertDebug(timestamp > 0);
        rawTimestamp = [timestamp unsignedLongLongValue];
    } else {
        rawTimestamp = 0;
    }

    return [[TSQuotedMessage alloc] initWithTimestamp:rawTimestamp
                                        authorAddress:authorAddress
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:bodySource
                         receivedQuotedAttachmentInfo:nil
                                          isGiftBadge:isGiftBadge];
}

+ (nullable TSAttachment *)quotedAttachmentFromOriginalMessage:(TSMessage *)quotedMessage
                                                   transaction:(SDSAnyWriteTransaction *)transaction
{
    if ([quotedMessage hasBodyAttachmentsWithTransaction:transaction]) {
        return [quotedMessage bodyAttachmentsWithTransaction:transaction].firstObject;
    }

    if (quotedMessage.linkPreview) {
        // If we have an image attachment, return it.
        TSAttachment *linkPreviewAttachment = [quotedMessage.linkPreview imageAttachmentForParentMessage:quotedMessage
                                                                                                      tx:transaction];
        if (linkPreviewAttachment) {
            return linkPreviewAttachment;
        }
    }

    if (quotedMessage.messageSticker && quotedMessage.messageSticker.attachmentId.length > 0) {
        return [TSAttachment anyFetchWithUniqueId:quotedMessage.messageSticker.attachmentId transaction:transaction];
    } else {
        return nil;
    }
}

- (nullable NSNumber *)getTimestampValue
{
    if (_timestamp == 0) {
        return nil;
    }
    return [[NSNumber alloc] initWithUnsignedLongLong:_timestamp];
}

#pragma mark - Private

/// Builds a quoted message from the original source message
+ (nullable TSQuotedMessage *)localQuotedMessageFromSourceMessage:(TSMessage *)quotedMessage
                                                       quoteProto:(SSKProtoDataMessageQuote *)proto
                                                 quoteProtoAuthor:(AciObjC *)quoteProtoAuthor
                                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *authorAddress = [[SignalServiceAddress alloc] initWithServiceIdObjC:quoteProtoAuthor];
    if (quotedMessage.isViewOnceMessage) {
        // We construct a quote that does not include any of the quoted message's renderable content.
        NSString *body = OWSLocalizedString(@"PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
            @"inbox cell and notification text for an already viewed view-once media message.");
        return [[TSQuotedMessage alloc] initWithTimestamp:quotedMessage.timestamp
                                            authorAddress:authorAddress
                                                     body:body
                                               bodyRanges:nil
                                               bodySource:TSQuotedMessageContentSourceLocal
                             receivedQuotedAttachmentInfo:nil
                                              isGiftBadge:NO];
    }

    NSString *_Nullable body = nil;
    MessageBodyRanges *_Nullable bodyRanges = nil;
    OWSAttachmentInfo *attachmentInfo = nil;
    BOOL isGiftBadge = NO;

    if (quotedMessage.body.length > 0) {
        body = quotedMessage.body;
        bodyRanges = quotedMessage.bodyRanges;

    } else if (quotedMessage.contactShare.name.displayName.length > 0) {
        // Contact share bodies are special-cased in OWSQuotedReplyModel
        // We need to account for that here.
        body = [@"👤 " stringByAppendingString:quotedMessage.contactShare.name.displayName];
    } else if (quotedMessage.storyReactionEmoji.length > 0) {
        NSString *formatString;
        if (authorAddress.isLocalAddress) {
            formatString = OWSLocalizedString(@"STORY_REACTION_QUOTE_FORMAT_SECOND_PERSON",
                @"quote text for a reaction to a story by the user (the header on the bubble says \"You\"). Embeds "
                @"{{reaction emoji}}");
        } else {
            formatString = OWSLocalizedString(@"STORY_REACTION_QUOTE_FORMAT_THIRD_PERSON",
                @"quote text for a reaction to a story by some other user (the header on the bubble says their name, "
                @"e.g. \"Bob\"). Embeds {{reaction emoji}}");
        }
        body = [NSString stringWithFormat:formatString, quotedMessage.storyReactionEmoji];
    } else if (quotedMessage.giftBadge != nil) {
        isGiftBadge = YES;
    }

    if ([quotedMessage conformsToProtocol:@protocol(OWSPaymentMessage)]) {
        // This really should recalculate the string from payment metadata.
        // But it does not.
        body = proto.text;
    }

    SSKProtoDataMessageQuoteQuotedAttachment *_Nullable firstAttachmentProto = proto.attachments.firstObject;

    if (firstAttachmentProto) {
        TSAttachment *toQuote = [self quotedAttachmentFromOriginalMessage:quotedMessage transaction:transaction];
        BOOL shouldThumbnail = [TSAttachmentStream hasThumbnailForMimeType:toQuote.contentType];

        if ([toQuote isKindOfClass:[TSAttachmentStream class]] && shouldThumbnail) {
            // We found an attachment stream on the original message! Use it as our quoted attachment
            TSAttachmentStream *thumbnail = [(TSAttachmentStream *)toQuote cloneAsThumbnail];
            [thumbnail anyInsertWithTransaction:transaction];

            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:thumbnail.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceThumbnail
                                                                 contentType:toQuote.contentType
                                                              sourceFilename:toQuote.sourceFilename];

        } else if ([toQuote isKindOfClass:[TSAttachmentPointer class]] && shouldThumbnail) {
            // No attachment stream, but we have a pointer. It's likely this media hasn't finished downloading yet.
            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:toQuote.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceOriginal
                                                                 contentType:toQuote.contentType
                                                              sourceFilename:toQuote.sourceFilename];
        } else if (toQuote) {
            // We have an attachment in the original message, but it doesn't support thumbnailing
            attachmentInfo = [[OWSAttachmentInfo alloc] initWithoutThumbnailWithContentType:toQuote.contentType
                                                                             sourceFilename:toQuote.sourceFilename];
        } else {
            // This could happen if a sender spoofs their quoted message proto.
            // Our quoted message will include no thumbnails.
            OWSFailDebug(@"Sender sent %lu quoted attachments. Local copy has none.", proto.attachments.count);
        }
    }

    if (body.length == 0 && !attachmentInfo && !isGiftBadge) {
        OWSFailDebug(@"quoted message has no content");
        return nil;
    }

    SignalServiceAddress *address = nil;
    if ([quotedMessage isKindOfClass:[TSIncomingMessage class]]) {
        address = ((TSIncomingMessage *)quotedMessage).authorAddress;
    } else if ([quotedMessage isKindOfClass:[TSOutgoingMessage class]]) {
        address = [TSAccountManagerObjcBridge localAciAddressWith:transaction];
    } else {
        OWSFailDebug(@"Received message of type: %@", NSStringFromClass(quotedMessage.class));
        return nil;
    }

    return [[TSQuotedMessage alloc] initWithTimestamp:quotedMessage.timestamp
                                        authorAddress:address
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:TSQuotedMessageContentSourceLocal
                         receivedQuotedAttachmentInfo:attachmentInfo
                                          isGiftBadge:isGiftBadge];
}

/// Builds a remote message from the proto payload
/// @note Quoted messages constructed from proto material may not be representative of the original source content. This
/// should be flagged to the user. (See: -[OWSQuotedReplyModel isRemotelySourced])
+ (nullable TSQuotedMessage *)remoteQuotedMessageFromQuoteProto:(SSKProtoDataMessageQuote *)proto
                                                    quoteAuthor:(AciObjC *)quoteAuthor
                                                    transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *quoteAuthorAddress = [[SignalServiceAddress alloc] initWithServiceIdObjC:quoteAuthor];

    // This is untrusted content from other users that may not be well-formed.
    // The GiftBadge type has no content/attachments, so don't read those
    // fields if the type is GiftBadge.
    if (proto.hasType && (proto.unwrappedType == SSKProtoDataMessageQuoteTypeGiftBadge)) {
        if (proto.id == 0) {
            OWSFailDebug(@"quoted message missing id");
            return nil;
        }
        uint64_t timestamp = [proto id];
        if (![SDS fitsInInt64:timestamp]) {
            OWSFailDebug(@"Invalid timestamp");
            return nil;
        }
        return [[TSQuotedMessage alloc] initWithTimestamp:timestamp
                                            authorAddress:quoteAuthorAddress
                                                     body:nil
                                               bodyRanges:nil
                                               bodySource:TSQuotedMessageContentSourceRemote
                             receivedQuotedAttachmentInfo:nil
                                              isGiftBadge:YES];
    }

    NSString *_Nullable body = nil;
    MessageBodyRanges *_Nullable bodyRanges = nil;
    OWSAttachmentInfo *attachmentInfo = nil;

    if (proto.text.length > 0) {
        body = proto.text;
    }
    if (proto.bodyRanges.count > 0) {
        bodyRanges = [[MessageBodyRanges alloc] initWithProtos:proto.bodyRanges];
    }

    // We're only interested in the first attachment
    SSKProtoDataMessageQuoteQuotedAttachment *_Nullable attachmentProto = proto.attachments.firstObject;
    SSKProtoAttachmentPointer *_Nullable thumbnailProto = attachmentProto.thumbnail;
    if (thumbnailProto) {
        TSAttachmentPointer *_Nullable thumbnailAttachment =
            [TSAttachmentPointer attachmentPointerFromProto:thumbnailProto albumMessage:nil];
        if (thumbnailAttachment) {
            [thumbnailAttachment anyInsertWithTransaction:transaction];
            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:thumbnailAttachment.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceUntrustedPointer
                                                                 contentType:attachmentProto.contentType
                                                              sourceFilename:attachmentProto.fileName];
        }
    }
    if (!attachmentInfo && attachmentProto) {
        attachmentInfo = [[OWSAttachmentInfo alloc] initWithoutThumbnailWithContentType:attachmentProto.contentType
                                                                         sourceFilename:attachmentProto.fileName];
    }

    if (body.length > 0 || attachmentInfo) {
        return [[TSQuotedMessage alloc] initWithTimestamp:proto.id
                                            authorAddress:quoteAuthorAddress
                                                     body:body
                                               bodyRanges:bodyRanges
                                               bodySource:TSQuotedMessageContentSourceRemote
                             receivedQuotedAttachmentInfo:attachmentInfo
                                              isGiftBadge:NO];
    } else {
        OWSFailDebug(@"Failed to construct a valid quoted message from remote proto content");
        return nil;
    }
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (id<QuotedMessageAttachmentHelper>)attachmentHelper
{
    return [QuotedMessageAttachmentHelperFactory helperFor:self.quotedAttachment];
}

- (nullable QuotedThumbnailAttachmentMetadata *)
    fetchThumbnailAttachmentMetadataForParentMessage:(TSMessage *)message
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.attachmentHelper thumbnailAttachmentMetadataWithParentMessage:message tx:transaction];
}

- (nullable NSString *)fetchThumbnailAttachmentIdForParentMessage:(id)message
                                                      transaction:(SDSAnyReadTransaction *)transaction
{
    return [[self.attachmentHelper thumbnailAttachmentMetadataWithParentMessage:message
                                                                             tx:transaction] thumbnailAttachmentId];
}

- (nullable DisplayableQuotedThumbnailAttachment *)
    displayableThumbnailAttachmentForMetadata:(QuotedThumbnailAttachmentMetadata *)metadata
                                parentMessage:(TSMessage *)message
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.attachmentHelper displayableThumbnailAttachmentWithMetadata:metadata
                                                               parentMessage:message
                                                                          tx:transaction];
}

- (nullable NSString *)attachmentPointerIdForDownloadingWithParentMessage:(TSMessage *)message
                                                              transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.attachmentHelper attachmentPointerIdForDownloadingWithParentMessage:message tx:transaction];
}

- (void)setDownloadedAttachmentStream:(TSAttachmentStream *)attachmentStream
                        parentMessage:(TSMessage *)message
                          transaction:(SDSAnyWriteTransaction *)transaction
{
    // Slightly confusing; this method delegates to the helper because behavior depends
    // on the attachment type and helper.
    // Legacy attachments route back to `setLegacyThumbnailAttachmentStream` below.
    // v2 attachments will instead update the AttachmentReferences table, not anything on TSQuotedMessage.
    [self.attachmentHelper setDownloadedAttachmentStreamWithAttachmentStream:attachmentStream
                                                               parentMessage:message
                                                                          tx:transaction];
}

- (void)setLegacyThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    self.quotedAttachment.attachmentType = OWSAttachmentInfoReferenceThumbnail;
    self.quotedAttachment.rawAttachmentId = attachmentStream.uniqueId;
}

- (nullable TSAttachmentStream *)createThumbnailAndUpdateMessageIfNecessaryWithParentMessage:(TSMessage *)message
                                                                                 transaction:(SDSAnyWriteTransaction *)
                                                                                                 transaction
{
    return [self.attachmentHelper createThumbnailAndUpdateMessageIfNecessaryWithParentMessage:message tx:transaction];
}

@end

NS_ASSUME_NONNULL_END
