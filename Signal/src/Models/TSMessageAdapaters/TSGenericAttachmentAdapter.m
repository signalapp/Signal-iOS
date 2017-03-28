//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSGenericAttachmentAdapter.h"
#import "AttachmentUploadView.h"
#import "TSAttachmentStream.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MimeTypeUtil.h>

@interface TSGenericAttachmentAdapter ()

@property (nonatomic) UIView *cachedMediaView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL incoming;
@property (nonatomic) NSString *attachmentId;

@end

@implementation TSGenericAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming
{
    self = [super init];

    if (self) {
        _attachment = attachment;
        _attachmentId = attachment.uniqueId;
        _incoming = incoming;
    }

    return self;
}

- (void)clearCachedMediaViews
{
    [super clearCachedMediaViews];
    _cachedMediaView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedMediaView = nil;
}

// TODO: Should we override hash or mediaHash?
- (NSUInteger)mediaHash
{
    return [self.attachment.uniqueId hash];
}

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)iconSize
{
    return 60.f;
}

- (CGFloat)hMargin
{
    return 10.f;
}

- (CGFloat)vMargin
{
    return 10.f;
}

- (UIFont *)attachmentLabelFont
{
    return [UIFont ows_regularFontWithSize:11.f];
}

- (UIFont *)fileTypeLabelFont
{
    return [UIFont ows_mediumFontWithSize:16.f];
}

- (UIView *)mediaView
{
    if (_cachedMediaView == nil) {
        CGSize viewSize = [self mediaViewDisplaySize];
        UIColor *textColor = (self.incoming ? [UIColor blackColor] : [UIColor whiteColor]);

        JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
        JSQMessagesBubbleImage *bubbleImageData = (self.incoming
                ? [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]]
                : [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]]);
        UIImage *bubbleImage = [bubbleImageData messageBubbleImage];
        OWSAssert(bubbleImage);
        UIImageView *bubbleImageView = [[UIImageView alloc] initWithImage:bubbleImage];
        _cachedMediaView = bubbleImageView;
        _cachedMediaView.frame = CGRectMake(0.f, 0.f, viewSize.width, viewSize.height);

        const CGFloat kBubbleTailWidth = 6.f;
        CGRect contentFrame = CGRectMake(self.incoming ? kBubbleTailWidth : 0.f,
            self.vMargin,
            viewSize.width - kBubbleTailWidth,
            viewSize.height - self.vMargin * 2.f);

        UIImage *image = [UIImage imageNamed:(self.incoming ? @"file-black-60" : @"file-white-60")];
        OWSAssert(image);
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        CGRect iconFrame = CGRectMake(round(contentFrame.origin.x + (contentFrame.size.width - self.iconSize) * 0.5f),
            round(contentFrame.origin.y),
            self.iconSize,
            self.iconSize);
        imageView.frame = iconFrame;
        [_cachedMediaView addSubview:imageView];

        NSString *fileExtension = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType];
        if (fileExtension.length < 1) {
            fileExtension = NSLocalizedString(@"GENERIC_ATTACHMENT_DEFAULT_TYPE",
                @"A default label for attachment whose file extension cannot be determined.");
        }

        UILabel *fileTypeLabel = [UILabel new];
        fileTypeLabel.text = fileExtension.uppercaseString;
        fileTypeLabel.textColor = textColor;
        fileTypeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        fileTypeLabel.font = [self fileTypeLabelFont];
        CGRect fileTypeLabelFrame = CGRectZero;
        fileTypeLabelFrame.size = [fileTypeLabel sizeThatFits:CGSizeZero];
        fileTypeLabelFrame.size.width = floor(MIN(self.iconSize * 0.5f, fileTypeLabelFrame.size.width));
        // Center on icon.
        fileTypeLabelFrame.origin.x
            = round(iconFrame.origin.x + (iconFrame.size.width - fileTypeLabelFrame.size.width) * 0.5f);
        fileTypeLabelFrame.origin.y
            = round(iconFrame.origin.y + (iconFrame.size.height - fileTypeLabelFrame.size.height) * 0.5f + 5);
        fileTypeLabel.frame = fileTypeLabelFrame;
        [_cachedMediaView addSubview:fileTypeLabel];

        UILabel *attachmentLabel = [UILabel new];
        attachmentLabel.text = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
        attachmentLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
        attachmentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        attachmentLabel.font = [self attachmentLabelFont];
        [attachmentLabel sizeToFit];
        CGRect attachmentLabelFrame = CGRectZero;
        attachmentLabelFrame.size = attachmentLabel.bounds.size;
        attachmentLabelFrame.origin.x
            = round(contentFrame.origin.x + (contentFrame.size.width - attachmentLabelFrame.size.width) * 0.5f);
        attachmentLabelFrame.origin.y
            = round(contentFrame.origin.y + contentFrame.size.height - attachmentLabelFrame.size.height);
        attachmentLabel.frame = attachmentLabelFrame;
        [_cachedMediaView addSubview:attachmentLabel];

        if (!self.incoming) {
            self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                               superview:_cachedMediaView
                                                                 attachmentStateCallback:nil];
        }
    }

    return _cachedMediaView;
}

- (CGSize)mediaViewDisplaySize
{
    const CGFloat kVSpacing = 1.f;
    return CGSizeMake(100, ceil(self.iconSize + self.attachmentLabelFont.lineHeight + kVSpacing + self.vMargin * 2));
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{
    if (action == @selector(copy:)) {
        NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachment.contentType];
        return utiType.length > 0;
    }
    return NO;
}

- (void)performEditingAction:(SEL)action
{
    if (action == @selector(copy:)) {
        NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachment.contentType];
        OWSAssert(utiType.length > 0);
        NSData *data = [NSData dataWithContentsOfURL:self.attachment.mediaURL];
        [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
    } else {
        // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
        NSString *actionString = NSStringFromSelector(action);
        DDLogError(@"'%@' action unsupported for %@: attachmentId=%@", actionString, [self class], self.attachmentId);
    }
}

@end
