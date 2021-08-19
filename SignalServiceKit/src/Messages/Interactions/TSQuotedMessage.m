//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

/// Indicates the sort of attachment ID included in the attachment info
typedef NS_ENUM(NSUInteger, OWSAttachmentInfoReference) {
    OWSAttachmentInfoReferenceUnset = 0,

    /// An attachment ID referencing original media
    /// This should only be used prior to sending a new quoted message. After sending, a copy of the source media should be thumbnailed
    /// and saved in its own attachment.
    /// An attachment ID referencing original media
    /// Indicates a valid handle to the original media, this may be a pointer to a pending download, or a stream.
    /// If a pointer, we should show the blurhash. If it's a stream, we should thumbnail the original and save in a separate attachment.
    /// An attachment ID referencing the quoted thumbnail
    /// This thumbnail may have been generated locally, or it may have been fetched remotely from the sender of the quoted message.
    /// An attachment ID referencing

    OWSAttachmentInfoReferenceOriginalForSend = 1,
    OWSAttachmentInfoReferenceOriginal,
    OWSAttachmentInfoReferenceThumbnail,
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

- (instancetype)initWithOriginalAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssertDebug(attachmentStream.uniqueId);
    OWSAssertDebug(attachmentStream.contentType);

    return [self initWithAttachmentId:attachmentStream.uniqueId
                               ofType:OWSAttachmentInfoReferenceOriginalForSend
                          contentType:attachmentStream.contentType
                       sourceFilename:attachmentStream.sourceFilename];
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

+ (NSUInteger)currentSchemaVersion {
    return 1;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_schemaVersion == 0) {
        NSString *_Nullable oldStreamId = [coder decodeObjectOfClass:[NSString class] forKey:@"thumbnailAttachmentStreamId"];
        NSString *_Nullable oldPointerId = [coder decodeObjectOfClass:[NSString class] forKey:@"thumbnailAttachmentPointerId"];
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

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable TSAttachmentStream *)attachment
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
        NSSet *expectedClasses = [NSSet setWithArray:@[[NSArray class], [OWSAttachmentInfo class]]];
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

    if (!quoteProto.hasValidAuthor) {
        OWSFailDebug(@"quoted message missing author");
        return nil;
    }

    TSQuotedMessage *_Nullable quotedMessage = nil;
    TSMessage *_Nullable originalMessage = [InteractionFinder findMessageWithTimestamp:timestamp
                                                                              threadId:thread.uniqueId
                                                                                author:quoteProto.authorAddress
                                                                           transaction:transaction];
    if (originalMessage) {
        // Prefer to generate the quoted content locally if available.
        quotedMessage = [self localQuotedMessageFromSourceMessage:originalMessage quoteProto:quoteProto transaction:transaction];
    }
    if (!quotedMessage) {
        // If we couldn't generate the quoted content from locally available info, we can generate it from the proto.
        quotedMessage = [self remoteQuotedMessageFromQuoteProto:quoteProto transaction:transaction];
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
                                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    if (quotedMessage.isViewOnceMessage) {
        // We construct a quote that does not include any of the quoted message's renderable content.
        NSString *body = NSLocalizedString(@"PER_MESSAGE_EXPIRATION_OUTGOING_MESSAGE",
                                           @"Label for outgoing view-once messages.");
        return [[TSQuotedMessage alloc] initWithTimestamp:quotedMessage.timestamp
                                            authorAddress:proto.authorAddress
                                                     body:body
                                               bodyRanges:nil
                                               bodySource:TSQuotedMessageContentSourceLocal
                             receivedQuotedAttachmentInfo:nil];
    }

    NSString *_Nullable body = nil;
    MessageBodyRanges *_Nullable bodyRanges = nil;
    OWSAttachmentInfo *attachmentInfo = nil;

    if (quotedMessage.body.length > 0) {
        body = quotedMessage.body;
        bodyRanges = quotedMessage.bodyRanges;

    } else if (quotedMessage.contactShare.name.displayName.length > 0) {
        // Contact share bodies are special-cased in OWSQuotedReplyModel
        // We need to account for that here.
        body = [@"👤 " stringByAppendingString:quotedMessage.contactShare.name.displayName];
    }

    SSKProtoDataMessageQuoteQuotedAttachment *_Nullable firstAttachmentProto = proto.attachments.firstObject;

    // TODO: Why are we trusting the contentType in the proto? Why does the filename matter?
    if (firstAttachmentProto && [TSAttachmentStream hasThumbnailForMimeType:firstAttachmentProto.contentType]) {
        TSAttachment *toQuote = [self quotedAttachmentFromOriginalMessage:quotedMessage transaction:transaction];

        if ([toQuote isKindOfClass:[TSAttachmentStream class]]) {
            // We found an attachment stream on the original message! Use it as our quoted attachment
            TSAttachmentStream *thumbnail = [(TSAttachmentStream *)toQuote cloneAsThumbnail];
            [thumbnail anyInsertWithTransaction:transaction];

            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:thumbnail.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceThumbnail
                                                                 contentType:firstAttachmentProto.contentType
                                                              sourceFilename:firstAttachmentProto.fileName];

        } else if ([toQuote isKindOfClass:[TSAttachmentPointer class]]) {
            // No attachment stream, but we have a pointer. It's likely this media hasn't finished downloading yet.
            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:toQuote.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceOriginal
                                                                 contentType:firstAttachmentProto.contentType
                                                              sourceFilename:firstAttachmentProto.fileName];
        } else {
            // This could happen if a sender spoofs their quoted message proto.
            // Our quoted message will include no thumbnails.
            OWSFailDebug(@"Sender sent %lu quoted attachments. Local copy has none.", proto.attachments.count);
        }
    }

    if (body.length == 0 && !attachmentInfo) {
        OWSFailDebug(@"quoted message has neither text nor attachment");
        return nil;
    }

    return [[TSQuotedMessage alloc] initWithTimestamp:quotedMessage.timestamp
                                        authorAddress:proto.authorAddress
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:TSQuotedMessageContentSourceLocal
                         receivedQuotedAttachmentInfo:attachmentInfo];
}

/// Builds a remote message from the proto payload
/// @note Quoted messages constructed from proto material may not be representative of the original source content. This should be flagged
/// to the user. (See: -[OWSQuotedReplyModel isRemotelySourced])
+ (nullable TSQuotedMessage *)remoteQuotedMessageFromQuoteProto:(SSKProtoDataMessageQuote *)proto
                                                    transaction:(SDSAnyWriteTransaction *)transaction
{
    NSString *_Nullable body = nil;
    MessageBodyRanges *_Nullable bodyRanges = nil;
    OWSAttachmentInfo *attachmentInfo = nil;

    if (proto.text.length > 0) {
        body = proto.text;
    }
    if (proto.bodyRanges.count > 0) {
        bodyRanges = [[MessageBodyRanges alloc] initWithProtos:proto.bodyRanges];
    }
    if (proto.attachments.count > 0) {
        // We only look at the first attachment
        SSKProtoAttachmentPointer *thumbnailProto = proto.attachments.firstObject.thumbnail;
        TSAttachmentPointer *_Nullable attachment = [TSAttachmentPointer attachmentPointerFromProto:thumbnailProto
                                                                                       albumMessage:nil];
        if (attachment) {
            [attachment anyInsertWithTransaction:transaction];
            attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:attachment.uniqueId
                                                                      ofType:OWSAttachmentInfoReferenceUntrustedPointer
                                                                 contentType:thumbnailProto.contentType
                                                              sourceFilename:thumbnailProto.fileName];
        } else {
            OWSFailDebug(@"Invalid remote thumbnail attachment.");
        }
    }

    if (body.length > 0 || attachmentInfo) {
        return [[TSQuotedMessage alloc] initWithTimestamp:proto.id
                                            authorAddress:proto.authorAddress
                                                     body:body
                                               bodyRanges:bodyRanges
                                               bodySource:TSQuotedMessageContentSourceRemote
                             receivedQuotedAttachmentInfo:attachmentInfo];
    } else {
        OWSFailDebug(@"Failed to construct a valid quoted message from remote proto content");
        return nil;
    }
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable TSAttachment *)fetchThumbnailWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSString *attachmentId = self.quotedAttachment.rawAttachmentId;
    TSAttachment *_Nullable attachment = nil;
    if (attachmentId) {
        attachment = [TSAttachment anyFetchWithUniqueId:self.quotedAttachment.rawAttachmentId transaction:transaction];
    }

    // If we have an attachment stream, we should've already thumbnailed the image.
    // TODO: This will fail if we've downloaded the original source media. We need to add a hook to flag
    // that we need to thumbnail the source to our own local copy
//
//    BOOL needsThumbnailing = (attachmentType == OWSAttachmentInfoReferenceUntrustedPointer) ||
//                             (attachmentType == OWSAttachmentInfoReferenceOriginal);
//    OWSAssertDebug(![attachment isKindOfClass:[TSAttachmentStream class]] || !needsThumbnailing);
    return attachment;
}

- (BOOL)isThumbnailOwned
{
    return (self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceUntrustedPointer || self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceThumbnail);
}

- (NSString *)contentType
{
    return self.quotedAttachment.contentType;
}

- (NSString *)sourceFilename
{
    return self.quotedAttachment.sourceFilename;
}

- (NSString *)thumbnailAttachmentId
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
    if (!self.quotedAttachment.rawAttachmentId) {
        return nil;
    }

    OWSAssertDebug(self.quotedAttachment.attachmentType == OWSAttachmentInfoReferenceOriginalForSend);
    NSString *attachmentId = self.quotedAttachment.rawAttachmentId;
    TSAttachmentStream *attachment = [TSAttachmentStream anyFetchAttachmentStreamWithUniqueId:attachmentId
                                                                                  transaction:transaction];
    TSAttachmentStream *thumbnail = [attachment cloneAsThumbnail];
    [thumbnail anyInsertWithTransaction:transaction];

    if (thumbnail) {
        self.quotedAttachment.attachmentType = OWSAttachmentInfoReferenceThumbnail;
        self.quotedAttachment.rawAttachmentId = thumbnail.uniqueId;
        return thumbnail;
    } else {
        OWSFailDebug(@"");
        self.quotedAttachment = nil;
        return nil;
    }
}

@end

NS_ASSUME_NONNULL_END
