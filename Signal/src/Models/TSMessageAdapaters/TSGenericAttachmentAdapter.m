//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSGenericAttachmentAdapter.h"
#import "AttachmentUploadView.h"
#import "TSAttachmentStream.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MimeTypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSGenericAttachmentAdapter ()

@property (nonatomic, nullable) UIView *cachedMediaView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL incoming;

// See comments on OWSMessageMediaAdapter.
@property (nonatomic, nullable, weak) id lastPresentingCell;

@end

#pragma mark -

@implementation TSGenericAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming
{
    self = [super init];

    if (self) {
        _attachment = attachment;
        _incoming = incoming;
    }

    return self;
}

- (NSString *)attachmentId
{
    return self.attachment.uniqueId;
}

- (void)clearAllViews
{
    [_cachedMediaView removeFromSuperview];
    _cachedMediaView = nil;
    _attachmentUploadView = nil;
}

- (void)clearCachedMediaViews
{
    [super clearCachedMediaViews];
    [self clearAllViews];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    [self clearAllViews];
}

// TODO: Should we override hash or mediaHash?
- (NSUInteger)mediaHash
{
    return [self.attachment.uniqueId hash];
}

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)bubbleHeight
{
    return 45.f;
}

- (CGFloat)iconSize
{
    return 40.f;
}

- (CGFloat)vMargin
{
    return 10.f;
}

- (UIView *)mediaView
{
    if (_cachedMediaView == nil) {
        CGSize viewSize = [self mediaViewDisplaySize];
        UIColor *textColor = (self.incoming ? [UIColor colorWithWhite:0.2 alpha:1.f] : [UIColor whiteColor]);

        _cachedMediaView = [[UIView alloc] initWithFrame:CGRectMake(0.f, 0.f, viewSize.width, viewSize.height)];

        _cachedMediaView.backgroundColor
            = self.incoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:_cachedMediaView
                                                                    isOutgoing:!self.incoming];

        const CGFloat kBubbleTailWidth = 6.f;
        CGRect contentFrame = CGRectMake(self.incoming ? kBubbleTailWidth : 0.f,
            self.vMargin,
            viewSize.width - kBubbleTailWidth - 15,
            viewSize.height - self.vMargin * 2);

        UIImage *image = [UIImage imageNamed:(self.incoming ? @"file-black-40" : @"file-white-40")];
        OWSAssert(image);
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        CGRect iconFrame = CGRectMake(round(contentFrame.origin.x + 10.f),
            round(contentFrame.origin.y + (contentFrame.size.height - self.iconSize) * 0.5f),
            self.iconSize,
            self.iconSize);
        imageView.frame = iconFrame;
        [_cachedMediaView addSubview:imageView];

        NSString *fileExtension = self.attachment.filePath.pathExtension;
        if (fileExtension.length < 1) {
            [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType];
        }
        if (fileExtension.length < 1) {
            fileExtension = NSLocalizedString(@"GENERIC_ATTACHMENT_DEFAULT_TYPE",
                @"A default label for attachment whose file extension cannot be determined.");
        }

        UILabel *fileTypeLabel = [UILabel new];
        fileTypeLabel.text = fileExtension.uppercaseString;
        fileTypeLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
        fileTypeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        fileTypeLabel.font = [UIFont ows_mediumFontWithSize:20.f];
        fileTypeLabel.adjustsFontSizeToFitWidth = YES;
        fileTypeLabel.textAlignment = NSTextAlignmentCenter;
        CGRect fileTypeLabelFrame = CGRectZero;
        fileTypeLabelFrame.size = [fileTypeLabel sizeThatFits:CGSizeZero];
        // This dimension depends on the space within the icon boundaries.
        fileTypeLabelFrame.size.width = 20.f;
        // Center on icon.
        fileTypeLabelFrame.origin.x
            = round(iconFrame.origin.x + (iconFrame.size.width - fileTypeLabelFrame.size.width) * 0.5f);
        fileTypeLabelFrame.origin.y
            = round(iconFrame.origin.y + (iconFrame.size.height - fileTypeLabelFrame.size.height) * 0.5f);
        fileTypeLabel.frame = fileTypeLabelFrame;
        [_cachedMediaView addSubview:fileTypeLabel];

        const CGFloat kLabelHSpacing = 3;
        const CGFloat kLabelVSpacing = 2;
        NSString *topText =
            [self.attachment.filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (topText.length < 1) {
            topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType].uppercaseString;
        }
        if (topText.length < 1) {
            topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
        }
        UILabel *topLabel = [UILabel new];
        topLabel.text = topText;
        topLabel.textColor = textColor;
        topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        topLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
        [topLabel sizeToFit];
        [_cachedMediaView addSubview:topLabel];

        NSError *error;
        unsigned long long fileSize =
            [[NSFileManager defaultManager] attributesOfItemAtPath:self.attachment.filePath error:&error].fileSize;
        OWSAssert(!error);
        NSString *bottomText = [ViewControllerUtils formatFileSize:fileSize];
        UILabel *bottomLabel = [UILabel new];
        bottomLabel.text = bottomText;
        bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
        bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        bottomLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
        [bottomLabel sizeToFit];
        [_cachedMediaView addSubview:bottomLabel];

        CGRect topLabelFrame = CGRectZero;
        topLabelFrame.size = topLabel.bounds.size;
        topLabelFrame.origin.x = round(iconFrame.origin.x + iconFrame.size.width + kLabelHSpacing);
        topLabelFrame.origin.y = round(contentFrame.origin.y
            + (contentFrame.size.height - (topLabel.frame.size.height + bottomLabel.frame.size.height + kLabelVSpacing))
                * 0.5f);
        topLabelFrame.size.width = round((contentFrame.origin.x + contentFrame.size.width) - topLabelFrame.origin.x);
        topLabel.frame = topLabelFrame;

        CGRect bottomLabelFrame = topLabelFrame;
        bottomLabelFrame.origin.y += topLabelFrame.size.height + kLabelVSpacing;
        bottomLabel.frame = bottomLabelFrame;

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
    CGSize size = [super mediaViewDisplaySize];
    size.height = ceil(self.bubbleHeight + self.vMargin * 2);
    return size;
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

#pragma mark - OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible
{
    // Ignore.
}

- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell
{
    OWSAssert(cell);

    if (cell == self.lastPresentingCell) {
        [self clearCachedMediaViews];
    }
}

@end

NS_ASSUME_NONNULL_END
