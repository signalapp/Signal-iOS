//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"
#import "TSAccountManager.h"
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

- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssertDebug(attachmentStream.uniqueId);
    OWSAssertDebug(attachmentStream.contentType);

    return [self initWithAttachmentId:attachmentStream.uniqueId
                          contentType:attachmentStream.contentType
                       sourceFilename:attachmentStream.sourceFilename];
}

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentId = attachmentId;
    _contentType = contentType;
    _sourceFilename = sourceFilename;

    return self;
}

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
        thumbnailAttachmentPointerId:(nullable NSString *)thumbnailAttachmentPointerId
         thumbnailAttachmentStreamId:(nullable NSString *)thumbnailAttachmentStreamId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentId = attachmentId;
    _contentType = contentType;
    _sourceFilename = sourceFilename;
    _thumbnailAttachmentPointerId = thumbnailAttachmentPointerId;
    _thumbnailAttachmentStreamId = thumbnailAttachmentStreamId;

    return self;
}

@end

@interface TSQuotedMessage ()

@property (atomic) NSArray<OWSAttachmentInfo *> *quotedAttachments;
@property (atomic) NSArray<TSAttachmentStream *> *quotedAttachmentsForSending;

@end

@implementation TSQuotedMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
    receivedQuotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos
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
    _quotedAttachments = attachmentInfos;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
      quotedAttachmentsForSending:(NSArray<TSAttachmentStream *> *)attachments
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

    NSMutableArray *attachmentInfos = [NSMutableArray new];
    for (TSAttachmentStream *attachmentStream in attachments) {
        [attachmentInfos addObject:[[OWSAttachmentInfo alloc] initWithAttachmentStream:attachmentStream]];
    }
    _quotedAttachments = [attachmentInfos copy];

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

    SignalServiceAddress *authorAddress = quoteProto.authorAddress;

    NSString *_Nullable body = nil;
    MessageBodyRanges *_Nullable bodyRanges = nil;
    BOOL hasAttachment = NO;
    TSQuotedMessageContentSource contentSource = TSQuotedMessageContentSourceUnknown;

    // Prefer to generate the text snippet locally if available.
    TSMessage *_Nullable quotedMessage = [InteractionFinder findMessageWithTimestamp:timestamp
                                                                            threadId:thread.uniqueId
                                                                              author:authorAddress
                                                                         transaction:transaction];

    if (quotedMessage) {
        contentSource = TSQuotedMessageContentSourceLocal;

        if (quotedMessage.isViewOnceMessage) {
            // We construct a quote that does not include any of the
            // quoted message's renderable content.
            body = NSLocalizedString(
                @"PER_MESSAGE_EXPIRATION_OUTGOING_MESSAGE", @"Label for outgoing view-once messages.");
            // Legit usage of senderTimestamp - this class references the message it is quoting by it's sender timestamp
            return [[TSQuotedMessage alloc] initWithTimestamp:timestamp
                                                authorAddress:authorAddress
                                                         body:body
                                                   bodyRanges:nil
                                                   bodySource:TSQuotedMessageContentSourceLocal
                                receivedQuotedAttachmentInfos:@[]];
        }

        if (quotedMessage.body.length > 0) {
            body = quotedMessage.body;
            bodyRanges = quotedMessage.bodyRanges;

        } else if (quotedMessage.contactShare.name.displayName.length > 0) {
            // Contact share bodies are special-cased in OWSQuotedReplyModel
            // We need to account for that here.
            body = [@"👤 " stringByAppendingString:quotedMessage.contactShare.name.displayName];
            bodyRanges = nil;
        }
    } else {
        OWSLogWarn(@"Could not find quoted message: %llu", timestamp);
        contentSource = TSQuotedMessageContentSourceRemote;
        if (quoteProto.text.length > 0) {
            body = quoteProto.text;
        }
        if (quoteProto.bodyRanges.count > 0) {
            bodyRanges = [[MessageBodyRanges alloc] initWithProtos:quoteProto.bodyRanges];
        }
    }

    OWSAssertDebug(contentSource != TSQuotedMessageContentSourceUnknown);

    NSMutableArray<OWSAttachmentInfo *> *attachmentInfos = [NSMutableArray new];
    for (SSKProtoDataMessageQuoteQuotedAttachment *quotedAttachment in quoteProto.attachments) {
        hasAttachment = YES;
        OWSAttachmentInfo *attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachmentId:nil
                                                                                contentType:quotedAttachment.contentType
                                                                             sourceFilename:quotedAttachment.fileName];

        // We prefer deriving any thumbnail locally rather than fetching one from the network.
        TSAttachmentStream *_Nullable localThumbnail =
            [self tryToDeriveLocalThumbnailWithTimestamp:timestamp
                                                threadId:thread.uniqueId
                                           authorAddress:authorAddress
                                             contentType:quotedAttachment.contentType
                                             transaction:transaction];

        if (localThumbnail) {
            OWSLogDebug(@"Generated local thumbnail for quoted quoted message: %@:%llu", thread.uniqueId, timestamp);
            // It would be surprising if we could derive a local thumbnail when
            // the body had to be derived remotely.
            OWSAssertDebug(contentSource == TSQuotedMessageContentSourceLocal);

            [localThumbnail anyInsertWithTransaction:transaction];

            attachmentInfo.thumbnailAttachmentStreamId = localThumbnail.uniqueId;
        } else if (quotedAttachment.thumbnail) {
            OWSLogDebug(@"Saving reference for fetching remote thumbnail for quoted message: %@:%llu",
                thread.uniqueId,
                timestamp);

            contentSource = TSQuotedMessageContentSourceRemote;
            SSKProtoAttachmentPointer *thumbnailAttachmentProto = quotedAttachment.thumbnail;
            TSAttachmentPointer *_Nullable thumbnailPointer =
                [TSAttachmentPointer attachmentPointerFromProto:thumbnailAttachmentProto albumMessage:nil];
            if (thumbnailPointer) {
                [thumbnailPointer anyInsertWithTransaction:transaction];

                attachmentInfo.thumbnailAttachmentPointerId = thumbnailPointer.uniqueId;
            } else {
                OWSFailDebug(@"Invalid thumbnail attachment.");
            }
        } else {
            OWSLogDebug(@"No thumbnail for quoted message: %@:%llu", thread.uniqueId, timestamp);
        }

        [attachmentInfos addObject:attachmentInfo];

        // For now, only support a single quoted attachment.
        break;
    }

    if (body.length == 0 && !hasAttachment) {
        OWSFailDebug(@"quoted message has neither text nor attachment");
        return nil;
    }

    // Legit usage of senderTimestamp - this class references the message it is quoting by it's sender timestamp
    return [[TSQuotedMessage alloc] initWithTimestamp:timestamp
                                        authorAddress:authorAddress
                                                 body:body
                                           bodyRanges:bodyRanges
                                           bodySource:contentSource
                        receivedQuotedAttachmentInfos:attachmentInfos];
}

+ (nullable TSAttachmentStream *)tryToDeriveLocalThumbnailWithTimestamp:(uint64_t)timestamp
                                                               threadId:(NSString *)threadId
                                                          authorAddress:(SignalServiceAddress *)authorAddress
                                                            contentType:(NSString *)contentType
                                                            transaction:(SDSAnyWriteTransaction *)transaction
{
    TSMessage *_Nullable quotedMessage = [InteractionFinder findMessageWithTimestamp:timestamp
                                                                            threadId:threadId
                                                                              author:authorAddress
                                                                         transaction:transaction];

    if (!quotedMessage) {
        OWSLogWarn(@"Could not find quoted message: %llu", timestamp);
        return nil;
    }

    TSAttachment *_Nullable attachmentToQuote = nil;
    if (quotedMessage.attachmentIds.count > 0) {
        attachmentToQuote = [quotedMessage bodyAttachmentsWithTransaction:transaction.unwrapGrdbRead].firstObject;
    } else if (quotedMessage.linkPreview && quotedMessage.linkPreview.imageAttachmentId.length > 0) {
        attachmentToQuote =
            [TSAttachment anyFetchWithUniqueId:quotedMessage.linkPreview.imageAttachmentId transaction:transaction];
    } else if (quotedMessage.messageSticker && quotedMessage.messageSticker.attachmentId.length > 0) {
        attachmentToQuote =
            [TSAttachment anyFetchWithUniqueId:quotedMessage.messageSticker.attachmentId transaction:transaction];
    }
    if (![attachmentToQuote isKindOfClass:[TSAttachmentStream class]]) {
        return nil;
    }
    if (![TSAttachmentStream hasThumbnailForMimeType:contentType]) {
        return nil;
    }
    TSAttachmentStream *sourceStream = (TSAttachmentStream *)attachmentToQuote;
    return [sourceStream cloneAsThumbnail];
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable OWSAttachmentInfo *)firstAttachmentInfo
{
    return self.quotedAttachments.firstObject;
}

- (nullable NSString *)contentType
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.contentType;
}

- (nullable NSString *)sourceFilename
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.sourceFilename;
}

- (nullable NSString *)thumbnailAttachmentPointerId
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.thumbnailAttachmentPointerId;
}

- (nullable NSString *)thumbnailAttachmentStreamId
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.thumbnailAttachmentStreamId;
}

- (void)setThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssertDebug(self.quotedAttachments.count == 1);

    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;
    firstAttachment.thumbnailAttachmentStreamId = attachmentStream.uniqueId;
}

- (NSArray<NSString *> *)thumbnailAttachmentStreamIds
{
    NSMutableArray *streamIds = [NSMutableArray new];
    for (OWSAttachmentInfo *info in self.quotedAttachments) {
        if (info.thumbnailAttachmentStreamId) {
            [streamIds addObject:info.thumbnailAttachmentStreamId];
        }
    }

    return [streamIds copy];
}

// Before sending, persist a thumbnail attachment derived from the quoted attachment
- (NSArray<TSAttachmentStream *> *)createThumbnailAttachmentsIfNecessaryWithTransaction:
    (SDSAnyWriteTransaction *)transaction
{
    NSMutableArray<TSAttachmentStream *> *thumbnailAttachments = [NSMutableArray new];

    for (OWSAttachmentInfo *info in self.quotedAttachments) {

        OWSAssertDebug(info.attachmentId);
        TSAttachment *attachment = [TSAttachment anyFetchWithUniqueId:info.attachmentId transaction:transaction];
        if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
            continue;
        }
        TSAttachmentStream *sourceStream = (TSAttachmentStream *)attachment;

        TSAttachmentStream *_Nullable thumbnailStream = [sourceStream cloneAsThumbnail];
        if (!thumbnailStream) {
            continue;
        }

        [thumbnailStream anyInsertWithTransaction:transaction];
        info.thumbnailAttachmentStreamId = thumbnailStream.uniqueId;
        [thumbnailAttachments addObject:thumbnailStream];
    }

    return [thumbnailAttachments copy];
}

@end

NS_ASSUME_NONNULL_END
