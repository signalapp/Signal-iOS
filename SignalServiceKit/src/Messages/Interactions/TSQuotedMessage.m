//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
#import <YapDatabase/YapDatabaseTransaction.h>

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
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                       bodySource:(TSQuotedMessageContentSource)bodySource
    receivedQuotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _bodySource = bodySource;
    _quotedAttachments = attachmentInfos;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
      quotedAttachmentsForSending:(NSArray<TSAttachmentStream *> *)attachments
{
    OWSAssertDebug(timestamp > 0);
    OWSAssertDebug(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _bodySource = TSQuotedMessageContentSourceLocal;

    NSMutableArray *attachmentInfos = [NSMutableArray new];
    for (TSAttachmentStream *attachmentStream in attachments) {
        [attachmentInfos addObject:[[OWSAttachmentInfo alloc] initWithAttachmentStream:attachmentStream]];
    }
    _quotedAttachments = [attachmentInfos copy];

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

    if (quoteProto.author.length == 0) {
        OWSFailDebug(@"quoted message missing author");
        return nil;
    }
    // TODO: We could verify that this is a valid e164 value.
    NSString *authorId = [quoteProto author];

    NSString *_Nullable body = nil;
    BOOL hasAttachment = NO;
    TSQuotedMessageContentSource bodySource = TSQuotedMessageContentSourceUnknown;

    // Prefer to generate the text snippet locally if available.
    TSMessage *_Nullable quotedMessage = [self findQuotedMessageWithTimestamp:timestamp
                                                                     threadId:thread.uniqueId
                                                                     authorId:authorId
                                                                  transaction:transaction];

    if (quotedMessage) {
        bodySource = TSQuotedMessageContentSourceLocal;

        NSString *localText = [quotedMessage bodyTextWithTransaction:transaction];
        if (localText.length > 0) {
            body = localText;
        }
    }

    if (body.length == 0) {
        if (quoteProto.text.length > 0) {
            bodySource = TSQuotedMessageContentSourceRemote;
            body = quoteProto.text;
        }
    }

    OWSAssertDebug(bodySource != TSQuotedMessageContentSourceUnknown);

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
                                                authorId:authorId
                                             contentType:quotedAttachment.contentType
                                             transaction:transaction];

        if (localThumbnail) {
            OWSLogDebug(@"Generated local thumbnail for quoted quoted message: %@:%lu",
                thread.uniqueId,
                (unsigned long)timestamp);

            [localThumbnail anyInsertWithTransaction:transaction];

            attachmentInfo.thumbnailAttachmentStreamId = localThumbnail.uniqueId;
        } else if (quotedAttachment.thumbnail) {
            OWSLogDebug(@"Saving reference for fetching remote thumbnail for quoted message: %@:%lu",
                thread.uniqueId,
                (unsigned long)timestamp);

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
            OWSLogDebug(@"No thumbnail for quoted message: %@:%lu", thread.uniqueId, (unsigned long)timestamp);
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
                                             authorId:authorId
                                                 body:body
                                           bodySource:bodySource
                        receivedQuotedAttachmentInfos:attachmentInfos];
}

+ (nullable TSAttachmentStream *)tryToDeriveLocalThumbnailWithTimestamp:(uint64_t)timestamp
                                                               threadId:(NSString *)threadId
                                                               authorId:(NSString *)authorId
                                                            contentType:(NSString *)contentType
                                                            transaction:(SDSAnyWriteTransaction *)transaction
{
    TSMessage *_Nullable quotedMessage =
        [self findQuotedMessageWithTimestamp:timestamp threadId:threadId authorId:authorId transaction:transaction];
    if (!quotedMessage) {
        return nil;
    }

    TSAttachment *_Nullable attachmentToQuote = nil;
    if (quotedMessage.attachmentIds.count > 0) {
        attachmentToQuote = [quotedMessage bodyAttachmentsWithTransaction:transaction].firstObject;
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

+ (nullable TSMessage *)findQuotedMessageWithTimestamp:(uint64_t)timestamp
                                              threadId:(NSString *)threadId
                                              authorId:(NSString *)authorId
                                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (timestamp <= 0) {
        OWSFailDebug(@"Invalid timestamp: %llu", timestamp);
        return nil;
    }
    if (threadId.length <= 0) {
        OWSFailDebug(@"Invalid thread.");
        return nil;
    }
    if (authorId.length <= 0) {
        OWSFailDebug(@"Invalid authorId: %@", authorId);
        return nil;
    }

    NSError *error;
    NSArray<TSInteraction *> *interactions =
        [InteractionFinder interactionsWithTimestamp:timestamp
                                              filter:^(TSInteraction *interaction) {
                                                  return [interaction isKindOfClass:[TSMessage class]];
                                              }
                                         transaction:transaction
                                               error:&error];
    if (error != nil) {
        OWSFailDebug(@"Error loading interactions: %@", error);
        return nil;
    }
    for (TSInteraction *interaction in interactions) {
        TSMessage *message = (TSMessage *)interaction;
        if (![message.uniqueThreadId isEqualToString:threadId]) {
            continue;
        }
        if ([message isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
            if (![authorId isEqual:incomingMessage.authorAddress.transitional_phoneNumber]) {
                continue;
            }
        } else if ([message isKindOfClass:[TSOutgoingMessage class]]) {
            if (![authorId isEqual:[TSAccountManager localNumber]]) {
                continue;
            }
        }

        return message;
    }
    OWSLogWarn(@"Could not find quoted message: %llu", timestamp);
    return nil;
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable OWSAttachmentInfo *)firstAttachmentInfo
{
    OWSAssertDebug(self.quotedAttachments.count <= 1);
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
