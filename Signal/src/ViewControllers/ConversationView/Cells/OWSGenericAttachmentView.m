//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSGenericAttachmentView.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/TSAttachmentStream.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSGenericAttachmentView ()

@property (nonatomic) TSAttachmentStream *attachmentStream;
@property (nonatomic) BOOL isIncoming;

@end

#pragma mark -

@implementation OWSGenericAttachmentView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream isIncoming:(BOOL)isIncoming
{
    self = [super init];

    if (self) {
        _attachmentStream = attachmentStream;
        _isIncoming = isIncoming;
    }

    return self;
}

#pragma mark - JSQMessageMediaData protocol

- (CGFloat)iconHMargin
{
    return 12.f;
}

- (CGFloat)iconHSpacing
{
    return 10.f;
}

+ (CGFloat)iconVMargin
{
    return 12.f;
}

- (CGFloat)iconVMargin
{
    return [OWSGenericAttachmentView iconVMargin];
}

+ (CGFloat)bubbleHeight
{
    return self.iconSize + self.iconVMargin * 2;
}

- (CGFloat)bubbleHeight
{
    return [OWSGenericAttachmentView bubbleHeight];
}

+ (CGFloat)iconSize
{
    return 40.f;
}

- (CGFloat)iconSize
{
    return [OWSGenericAttachmentView iconSize];
}

- (CGFloat)vMargin
{
    return 10.f;
}

- (UIColor *)bubbleBackgroundColor
{
    return self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
}

- (UIColor *)textColor
{
    return (self.isIncoming ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor whiteColor]);
}

- (UIColor *)foregroundColorWithOpacity:(CGFloat)alpha
{
    return [self.textColor blendWithColor:self.bubbleBackgroundColor alpha:alpha];
}

- (void)createContents
{
    UIColor *textColor = (self.isIncoming ? [UIColor colorWithWhite:0.2 alpha:1.f] : [UIColor whiteColor]);

    self.backgroundColor = self.bubbleBackgroundColor;
    self.layoutMargins = UIEdgeInsetsZero;

    // TODO: Verify that this layout works in RTL.
    const CGFloat kBubbleTailWidth = 6.f;

    UIView *contentView = [UIView containerView];
    [self addSubview:contentView];
    [contentView autoPinLeadingToSuperviewWithMargin:self.isIncoming ? kBubbleTailWidth : 0.f];
    [contentView autoPinTrailingToSuperviewWithMargin:self.isIncoming ? 0.f : kBubbleTailWidth];
    [contentView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.vMargin];
    [contentView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.vMargin];

    UIImage *image = [UIImage imageNamed:@"generic-attachment-small"];
    OWSAssert(image);
    UIImageView *imageView = [UIImageView new];
    imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageView.tintColor = self.bubbleBackgroundColor;
    imageView.backgroundColor
        = (self.isIncoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self foregroundColorWithOpacity:0.15f]);
    imageView.layer.cornerRadius = MIN(imageView.bounds.size.width, imageView.bounds.size.height) * 0.5f;
    [contentView addSubview:imageView];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:self.iconHMargin];
    [imageView autoVCenterInSuperview];
    [imageView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [imageView autoSetDimension:ALDimensionHeight toSize:self.iconSize];

    const CGFloat kLabelHSpacing = self.iconHSpacing;
    UIView *labelsView = [UIView containerView];
    [contentView addSubview:labelsView];
    [labelsView autoPinLeadingToTrailingOfView:imageView margin:kLabelHSpacing];
    [labelsView autoPinEdgeToSuperviewEdge:ALEdgeRight];
    [labelsView autoVCenterInSuperview];

    NSString *filename = self.attachmentStream.sourceFilename;
    if (!filename) {
        filename = [[self.attachmentStream filePath] lastPathComponent];
    }
    NSString *fileExtension = filename.pathExtension;
    if (fileExtension.length < 1) {
        [MIMETypeUtil fileExtensionForMIMEType:self.attachmentStream.contentType];
    }
    if (fileExtension.length < 1) {
        fileExtension = NSLocalizedString(@"GENERIC_ATTACHMENT_DEFAULT_TYPE",
            @"A default label for attachment whose file extension cannot be determined.");
    }

    UILabel *fileTypeLabel = [UILabel new];
    fileTypeLabel.text = fileExtension.uppercaseString;
    fileTypeLabel.textColor = imageView.backgroundColor;
    fileTypeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    fileTypeLabel.font = [UIFont ows_mediumFontWithSize:20.f];
    fileTypeLabel.adjustsFontSizeToFitWidth = YES;
    fileTypeLabel.textAlignment = NSTextAlignmentCenter;
    // Center on icon.
    [imageView addSubview:fileTypeLabel];
    [imageView autoCenterInSuperview];
    [imageView autoSetDimension:ALDimensionWidth toSize:15.f];

    const CGFloat kLabelVSpacing = 2;
    NSString *topText =
        [self.attachmentStream.sourceFilename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachmentStream.contentType].uppercaseString;
    }
    if (topText.length < 1) {
        topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
    }
    UILabel *topLabel = [UILabel new];
    topLabel.text = topText;
    topLabel.textColor = textColor;
    topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    topLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    topLabel.textAlignment = NSTextAlignmentLeft;
    [labelsView addSubview:topLabel];
    [topLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [topLabel autoPinWidthToSuperview];

    NSError *error;
    unsigned long long fileSize =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[self.attachmentStream filePath] error:&error].fileSize;
    OWSAssert(!error);
    NSString *bottomText = [ViewControllerUtils formatFileSize:fileSize];
    UILabel *bottomLabel = [UILabel new];
    bottomLabel.text = bottomText;
    bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(11.f, 13.f)];
    [labelsView addSubview:bottomLabel];
    [bottomLabel autoPinWidthToSuperview];
    [bottomLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topLabel withOffset:kLabelVSpacing];
    [bottomLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];
}

@end

NS_ASSUME_NONNULL_END
