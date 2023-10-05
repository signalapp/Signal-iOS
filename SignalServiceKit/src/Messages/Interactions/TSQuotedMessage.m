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

/// Indicates the sort of attachment ID included in the attachment info
typedef NS_ENUM(NSUInteger, OWSAttachmentInfoReference) {
    OWSAttachmentInfoReferenceUnset = 0,
    /// An original attachment for a quoted reply draft. This needs to be thumbnailed before it is sent.
    OWSAttachmentInfoReferenceOriginalForSend = 1,
    /// A reference to an original attachment in a quoted reply we've received. If this ever manifests as a stream
    /// we should clone it as a private thumbnail
    OWSAttachmentInfoReferenceOriginal,
    /// A private thumbnail that we (the quoted reply) have ownership of
    OWSAttachmentInfoReferenceThumbnail,
    /// An untrusted pointer to a thumbnail. This was included in the proto of a message we've received.
    OWSAttachmentInfoReferenceUntrustedPointer,
};

@interface OWSAttachmentInfo : MTLModel
@property (class, nonatomic, readonly) NSUInteger currentSchemaVersion;
@property (nonatomic, readonly) NSUInteger schemaVersion;

@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic) OWSAttachmentInfoReference attachmentType;
@property (nonatomic) NSString *rawAttachmentId;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation OWSAttachmentInfo

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
@property (nonatomic, nullable) OWSAttachmentInfo *quotedAttachment;
@end

@implementation TSQuotedMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
     receivedQuotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(timestamp > 0);
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

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable TSAttachmentStream *)attachment
                      isGiftBadge:(BOOL)isGiftBadge
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorAddress.isValid);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
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
        _authorAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:[coder decodeObjectForKey:@"authorId"]];
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

+ (nullable TSAttachment *)quotedAttachmentFromOriginalMessage:(TSMessage *)quotedMessage
                                                   transaction:(SDSAnyWriteTransaction *)transaction
{
    if (quotedMessage.attachmentIds.count > 0) {
        return [quotedMessage bodyAttachmentsWithTransaction:transaction.unwrapGrdbRead].firstObject;
    } else if (quotedMessage.linkPreview && quotedMessage.linkPreview.imageAttachmentId.length > 0) {
        return [TSAttachment anyFetchWithUniqueId:quotedMessage.linkPreview.imageAttachmentId transaction:transaction];
    } else if (quotedMessage.messageSticker && quotedMessage.messageSticker.attachmentId.length > 0) {
        return [TSAttachment anyFetchWithUniqueId:quotedMessage.messageSticker.attachmentId transaction:transaction];
    } else {
        return nil;
    }
}

#pragma mark - Private

/// Builds a quoted message from the original source message
+ (nullable TSQuotedMessage *)localQuotedMessageFromSourceMessage:(TSMessage *)quotedMessage
                                                       quoteProto:(SSKProtoDataMessageQuote *)proto
                                                 quoteProtoAuthor:(AciObjC *)quoteProtoAuthor
                                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    if (quotedMessage.isViewOnceMessage) {
        // We construct a quote that does not include any of the quoted message's renderable content.
        NSString *body = OWSLocalizedString(@"PER_MESSAGE_EXPIRATION_NOT_VIEWABLE",
            @"inbox cell and notification text for an already viewed view-once media message.");
        return [[TSQuotedMessage alloc]
                       initWithTimestamp:quotedMessage.timestamp
                           authorAddress:[[SignalServiceAddress alloc] initWithServiceIdObjC:quoteProtoAuthor]
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
        body = [NSString stringWithFormat:OWSLocalizedString(@"STORY_REACTION_QUOTE_FORMAT",
                                              @"quote text for a reaction to a story. Embeds {{reaction emoji}}"),
                         quotedMessage.storyReactionEmoji];
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
        return [[TSQuotedMessage alloc] initWithTimestamp:proto.id
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

- (BOOL)hasAttachment
{
    return (self.quotedAttachment != nil);
}

- (nullable TSAttachment *)fetchThumbnailWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *attachmentId = self.quotedAttachment.rawAttachmentId;
    TSAttachment *_Nullable attachment = nil;
    if (attachmentId) {
        attachment = [TSAttachment anyFetchWithUniqueId:self.quotedAttachment.rawAttachmentId transaction:transaction];
    }
    return attachment;
}

- (BOOL)isThumbnailOwned
{
    return (self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceUntrustedPointer
        || self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceThumbnail);
}

- (nullable NSString *)contentType
{
    return self.quotedAttachment.contentType;
}

- (nullable NSString *)sourceFilename
{
    return self.quotedAttachment.sourceFilename;
}

- (nullable NSString *)thumbnailAttachmentId
{
    return self.quotedAttachment.rawAttachmentId;
}

- (void)setThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);

    // If we're updating the attachmentId, it should be because we've downloaded the thumbnail from a remote source
    if (self.quotedAttachment.rawAttachmentId != attachmentStream.uniqueId) {
        OWSAssertDebug(self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceUntrustedPointer);
    }

    self.quotedAttachment.attachmentType = OWSAttachmentInfoReferenceThumbnail;
    self.quotedAttachment.rawAttachmentId = attachmentStream.uniqueId;
}

- (nullable TSAttachmentStream *)createThumbnailIfNecessaryWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // We want to clone the existing attachment to a new attachment if necessary. This means:
    // - Fetching the attachment and making sure it's an attachment stream
    // - If we already own the attachment, we've already cloned it!
    // - Otherwise, we should copy the attachment stream to a new attachment
    // - Updating our state to now point to the new attachment
    NSString *_Nullable attachmentId = self.quotedAttachment.rawAttachmentId;
    if (!attachmentId) {
        return nil;
    }

    TSAttachment *_Nullable attachment = [TSAttachment anyFetchWithUniqueId:attachmentId transaction:transaction];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        // Nothing to clone
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    TSAttachmentStream *_Nullable thumbnail = nil;

    // We don't expect to be here in this state. Remote pointers are set via -setThumbnailAttachmentStream:
    // If we have a stream and we're still in this state, something went wrong.
    OWSAssertDebug(self.quotedAttachment.attachmentType != OWSAttachmentInfoReferenceUntrustedPointer);
    if (!self.isThumbnailOwned) {
        OWSLogInfo(@"Cloning attachment to thumbnail");
        thumbnail = [attachmentStream cloneAsThumbnail];
        [thumbnail anyInsertWithTransaction:transaction];
        self.quotedAttachment.rawAttachmentId = thumbnail.uniqueId;
        self.quotedAttachment.attachmentType = OWSAttachmentInfoReferenceThumbnail;
    } else {
        thumbnail = attachmentStream;
    }
    return thumbnail;
}

@end

NS_ASSUME_NONNULL_END
