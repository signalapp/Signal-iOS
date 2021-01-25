//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSQuotedReplyModel.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSQuotedReplyModel ()

@property (nonatomic, readonly) TSQuotedMessageContentSource bodySource;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
                   thumbnailImage:(nullable UIImage *)thumbnailImage
                      contentType:(nullable NSString *)contentType
                   sourceFilename:(nullable NSString *)sourceFilename
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
       thumbnailAttachmentPointer:(nullable TSAttachmentPointer *)thumbnailAttachmentPointer
          thumbnailDownloadFailed:(BOOL)thumbnailDownloadFailed NS_DESIGNATED_INITIALIZER;

@end

// View Model which has already fetched any thumbnail attachment.
@implementation OWSQuotedReplyModel

#pragma mark - Initializers

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
                   thumbnailImage:(nullable UIImage *)thumbnailImage
                      contentType:(nullable NSString *)contentType
                   sourceFilename:(nullable NSString *)sourceFilename
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
       thumbnailAttachmentPointer:(nullable TSAttachmentPointer *)thumbnailAttachmentPointer
          thumbnailDownloadFailed:(BOOL)thumbnailDownloadFailed
{
    self = [super init];
    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _authorAddress = authorAddress;
    _body = body;
    _bodyRanges = bodyRanges;
    _bodySource = bodySource;
    _thumbnailImage = thumbnailImage;
    _contentType = contentType;
    _sourceFilename = sourceFilename;
    _attachmentStream = attachmentStream;
    _thumbnailAttachmentPointer = thumbnailAttachmentPointer;
    _thumbnailDownloadFailed = thumbnailDownloadFailed;

    return self;
}

#pragma mark - Factory Methods

+ (instancetype)quotedReplyWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(quotedMessage.quotedAttachments.count <= 1);
    OWSAttachmentInfo *attachmentInfo = quotedMessage.quotedAttachments.firstObject;

    BOOL thumbnailDownloadFailed = NO;
    UIImage *_Nullable thumbnailImage;
    TSAttachmentPointer *attachmentPointer;
    if (attachmentInfo.thumbnailAttachmentStreamId) {
        TSAttachment *attachment =
            [TSAttachment anyFetchWithUniqueId:attachmentInfo.thumbnailAttachmentStreamId transaction:transaction];

        TSAttachmentStream *attachmentStream;
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            attachmentStream = (TSAttachmentStream *)attachment;
            thumbnailImage = attachmentStream.thumbnailImageSmallSync;
        }
    } else if (attachmentInfo.thumbnailAttachmentPointerId) {
        // download failed, or hasn't completed yet.
        TSAttachment *attachment =
            [TSAttachment anyFetchWithUniqueId:attachmentInfo.thumbnailAttachmentPointerId transaction:transaction];

        if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            attachmentPointer = (TSAttachmentPointer *)attachment;
            if (attachmentPointer.state == TSAttachmentPointerStateFailed) {
                thumbnailDownloadFailed = YES;
            }
        }
    }

    return [[self alloc] initWithTimestamp:quotedMessage.timestamp
                             authorAddress:quotedMessage.authorAddress
                                      body:quotedMessage.body
                                bodyRanges:quotedMessage.bodyRanges
                                bodySource:quotedMessage.bodySource
                            thumbnailImage:thumbnailImage
                               contentType:attachmentInfo.contentType
                            sourceFilename:attachmentInfo.sourceFilename
                          attachmentStream:nil
                thumbnailAttachmentPointer:attachmentPointer
                   thumbnailDownloadFailed:thumbnailDownloadFailed];
}

+ (nullable instancetype)quotedReplyForSendingWithItem:(id<CVItemViewModel>)item
                                           transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    TSInteraction *interaction = item.interaction;
    if (![interaction isKindOfClass:[TSMessage class]]) {
        OWSFailDebug(@"unexpected reply message: %@", interaction);
        return nil;
    }
    TSMessage *message = (TSMessage *)(interaction);

    TSThread *thread = [message threadWithTransaction:transaction];
    OWSAssertDebug(thread);

    uint64_t timestamp = message.timestamp;

    SignalServiceAddress *_Nullable authorAddress = ^{
        if ([message isKindOfClass:[TSOutgoingMessage class]]) {
            return [TSAccountManager localAddressWithTransaction:transaction];
        } else if ([message isKindOfClass:[TSIncomingMessage class]]) {
            return [(TSIncomingMessage *)message authorAddress];
        } else {
            OWSFailDebug(@"Unexpected message type: %@", message.class);
            return (SignalServiceAddress * _Nullable) nil;
        }
    }();
    OWSAssertDebug(authorAddress.isValid);

    if (message.isViewOnceMessage) {
        // We construct a quote that does not include any of the
        // quoted message's renderable content.
        NSString *body
            = NSLocalizedString(@"PER_MESSAGE_EXPIRATION_NOT_VIEWABLE", @"inbox cell and notification text for an already viewed view-once media message.");
        return [[self alloc] initWithTimestamp:timestamp
                                 authorAddress:authorAddress
                                          body:body
                                    bodyRanges:nil
                                    bodySource:TSQuotedMessageContentSourceLocal
                                thumbnailImage:nil
                                   contentType:nil
                                sourceFilename:nil
                              attachmentStream:nil
                    thumbnailAttachmentPointer:nil
                       thumbnailDownloadFailed:NO];
    }

    if (item.contactShare) {
        ContactShareViewModel *contactShare = item.contactShare;

        // TODO We deliberately always pass `nil` for `thumbnailImage`, even though we might have a contactShare.avatarImage
        // because the QuotedReplyViewModel has some hardcoded assumptions that only quoted attachments have
        // thumbnails. Until we address that we want to be consistent about neither showing nor sending the
        // contactShare avatar in the quoted reply.
        return [[self alloc] initWithTimestamp:timestamp
                                 authorAddress:authorAddress
                                          body:[@"👤 " stringByAppendingString:contactShare.displayName]
                                    bodyRanges:nil
                                    bodySource:TSQuotedMessageContentSourceLocal
                                thumbnailImage:nil
                                   contentType:nil
                                sourceFilename:nil
                              attachmentStream:nil
                    thumbnailAttachmentPointer:nil
                       thumbnailDownloadFailed:NO];
    }

    if (item.stickerInfo || item.stickerAttachment || item.stickerMetadata) {
        if (!item.stickerInfo || !item.stickerAttachment || !item.stickerMetadata) {
            OWSFailDebug(@"Incomplete sticker message.");
            return nil;
        }

        TSAttachmentStream *quotedAttachment = item.stickerAttachment;
        StickerMetadata *stickerMetadata = item.stickerMetadata;
        NSData *_Nullable stickerData = [NSData dataWithContentsOfURL:stickerMetadata.stickerDataUrl];
        if (!stickerData) {
            OWSFailDebug(@"Couldn't load sticker data.");
            return nil;
        }

        // Sticker type metadata isn't reliable, so determine the
        // sticker type by examining the actual sticker data.
        StickerType stickerType = stickerMetadata.stickerType;
        NSString *_Nullable contentType = stickerMetadata.contentType;
        if (stickerType == StickerTypeWebp) {
            ImageMetadata *imageMetadata = [stickerData imageMetadataWithPath:nil mimeType:nil];
            switch (imageMetadata.imageFormat) {
                case ImageFormat_Unknown:
                    OWSFailDebug(@"Unknown sticker data format.");
                    return nil;
                case ImageFormat_Png:
                    stickerType = StickerTypeApng;
                    contentType = imageMetadata.mimeType;
                    break;
                case ImageFormat_Gif:
                    stickerType = StickerTypeGif;
                    contentType = imageMetadata.mimeType;
                    break;
                case ImageFormat_Webp:
                    stickerType = StickerTypeWebp;
                    contentType = imageMetadata.mimeType;
                    break;
                case ImageFormat_LottieSticker:
                    stickerType = StickerTypeSignalLottie;
                    contentType = imageMetadata.mimeType;
                    break;
                default:
                    OWSFailDebug(
                        @"Invalid sticker data format: %@.", NSStringForImageFormat(imageMetadata.imageFormat));
                    return nil;
            }
        }

        const CGFloat kMaxThumbnailSizePixels = 512;
        UIImage *_Nullable thumbnailImage;
        switch (stickerType) {
            case StickerTypeWebp:
                thumbnailImage = [stickerData stillForWebpData];
                break;
            case StickerTypeApng:
                thumbnailImage = [UIImage imageWithData:stickerData];
                break;
            case StickerTypeSignalLottie:
                break;
            case StickerTypeGif: {
                NSError *_Nullable error;
                thumbnailImage = [OWSMediaUtils thumbnailForImageAtPath:stickerMetadata.stickerDataUrl.path
                                                           maxDimension:kMaxThumbnailSizePixels
                                                                  error:&error];
                if (error != nil || thumbnailImage == nil) {
                    OWSFailDebug(@"Error: %@", error);
                    thumbnailImage = nil;
                }
                break;
            }
        }
        if (!thumbnailImage) {
            OWSFailDebug(@"Couldn't generate thumbnail for sticker.");
            return nil;
        }
        thumbnailImage = [thumbnailImage resizedWithMaxDimensionPixels:kMaxThumbnailSizePixels];

        return [[self alloc] initWithTimestamp:timestamp
                                 authorAddress:authorAddress
                                          body:nil
                                    bodyRanges:nil
                                    bodySource:TSQuotedMessageContentSourceLocal
                                thumbnailImage:thumbnailImage
                                   contentType:contentType
                                sourceFilename:quotedAttachment.sourceFilename
                              attachmentStream:quotedAttachment
                    thumbnailAttachmentPointer:nil
                       thumbnailDownloadFailed:NO];
    }

    NSString *_Nullable quotedText = message.body;
    BOOL hasText = quotedText.length > 0;

    TSAttachment *_Nullable attachment =
        [message bodyAttachmentsWithTransaction:transaction.unwrapGrdbRead].firstObject;
    TSAttachmentStream *quotedAttachment;
    if (attachment && [attachment isKindOfClass:[TSAttachmentStream class]]) {

        TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

        // If the attachment is "oversize text", try the quote as a reply to text, not as
        // a reply to an attachment.
        if (!hasText && [OWSMimeTypeOversizeTextMessage isEqualToString:attachment.contentType]) {
            hasText = YES;
            quotedText = @"";

            NSData *_Nullable oversizeTextData = [NSData dataWithContentsOfFile:attachmentStream.originalFilePath];
            if (oversizeTextData) {
                // We don't need to include the entire text body of the message, just
                // enough to render a snippet.  kOversizeTextMessageSizeThreshold is our
                // limit on how long text should be in protos since they'll be stored in
                // the database. We apply this constant here for the same reasons.
                NSString *_Nullable oversizeText =
                    [[NSString alloc] initWithData:oversizeTextData encoding:NSUTF8StringEncoding];
                // First, truncate to the rough max characters.
                NSString *_Nullable truncatedText =
                    [oversizeText substringToIndex:kOversizeTextMessageSizeThreshold - 1];
                // But kOversizeTextMessageSizeThreshold is in _bytes_, not characters,
                // so we need to continue to trim the string until it fits.
                while (truncatedText && truncatedText.length > 0 &&
                    [truncatedText dataUsingEncoding:NSUTF8StringEncoding].length
                        >= kOversizeTextMessageSizeThreshold) {
                    // A very coarse binary search by halving is acceptable, since
                    // kOversizeTextMessageSizeThreshold is much longer than our target
                    // length of "three short lines of text on any device we might
                    // display this on.
                    //
                    // The search will always converge since in the worst case (namely
                    // a single character which in utf-8 is >= 1024 bytes) the loop will
                    // exit when the string is empty.
                    truncatedText = [truncatedText substringToIndex:truncatedText.length / 2];
                }
                if ([truncatedText dataUsingEncoding:NSUTF8StringEncoding].length < kOversizeTextMessageSizeThreshold) {
                    quotedText = truncatedText;
                } else {
                    OWSFailDebug(@"Missing valid text snippet.");
                }
            }
        } else {
            quotedAttachment = attachmentStream;
        }
    }

    if (!quotedAttachment && item.linkPreview && item.linkPreviewAttachment &&
        [item.linkPreviewAttachment isKindOfClass:[TSAttachmentStream class]]) {

        quotedAttachment = (TSAttachmentStream *)item.linkPreviewAttachment;
    }

    BOOL hasAttachment = quotedAttachment != nil;
    if (!hasText && !hasAttachment) {
        OWSFailDebug(@"quoted message has neither text nor attachment");
        quotedText = @"";
        hasText = YES;
    }

    UIImage *_Nullable thumbnailImage;
    if (quotedAttachment.isValidVisualMedia) {
        thumbnailImage = quotedAttachment.thumbnailImageSmallSync;
    }
    return [[self alloc] initWithTimestamp:timestamp
                             authorAddress:authorAddress
                                      body:quotedText
                                bodyRanges:message.bodyRanges
                                bodySource:TSQuotedMessageContentSourceLocal
                            thumbnailImage:thumbnailImage
                               contentType:quotedAttachment.contentType
                            sourceFilename:quotedAttachment.sourceFilename
                          attachmentStream:quotedAttachment
                thumbnailAttachmentPointer:nil
                   thumbnailDownloadFailed:NO];
}

#pragma mark - Instance Methods

- (TSQuotedMessage *)buildQuotedMessageForSending
{
    NSArray *attachments = self.attachmentStream ? @[ self.attachmentStream ] : @[];

    // Legit usage of senderTimestamp to reference existing message
    return [[TSQuotedMessage alloc] initWithTimestamp:self.timestamp
                                        authorAddress:self.authorAddress
                                                 body:self.body
                                           bodyRanges:self.bodyRanges
                          quotedAttachmentsForSending:attachments];
}

- (BOOL)isRemotelySourced
{
    return self.bodySource == TSQuotedMessageContentSourceRemote;
}

@end

NS_ASSUME_NONNULL_END
