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

- (void)createContentsForSize:(CGSize)viewSize
{
    UIColor *textColor = (self.isIncoming ? [UIColor colorWithWhite:0.2 alpha:1.f] : [UIColor whiteColor]);

    self.backgroundColor = self.bubbleBackgroundColor;

    const CGFloat kBubbleTailWidth = 6.f;
    CGRect contentFrame = CGRectMake(self.isIncoming ? kBubbleTailWidth : 0.f,
        self.vMargin,
        viewSize.width - kBubbleTailWidth - self.iconHMargin,
        viewSize.height - self.vMargin * 2);

    UIImage *image = [UIImage imageNamed:@"generic-attachment-small"];
    OWSAssert(image);
    UIImageView *imageView = [UIImageView new];
    CGRect iconFrame = CGRectMake(round(contentFrame.origin.x + self.iconHMargin),
        round(contentFrame.origin.y + (contentFrame.size.height - self.iconSize) * 0.5f),
        self.iconSize,
        self.iconSize);
    imageView.frame = iconFrame;
    imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageView.tintColor = self.bubbleBackgroundColor;
    imageView.backgroundColor
        = (self.isIncoming ? [UIColor colorWithRGBHex:0x9e9e9e] : [self foregroundColorWithOpacity:0.15f]);
    imageView.layer.cornerRadius = MIN(imageView.bounds.size.width, imageView.bounds.size.height) * 0.5f;
    [self addSubview:imageView];

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
    CGRect fileTypeLabelFrame = CGRectZero;
    fileTypeLabelFrame.size = [fileTypeLabel sizeThatFits:CGSizeZero];
    // This dimension depends on the space within the icon boundaries.
    fileTypeLabelFrame.size.width = 15.f;
    // Center on icon.
    fileTypeLabelFrame.origin.x
        = round(iconFrame.origin.x + (iconFrame.size.width - fileTypeLabelFrame.size.width) * 0.5f);
    fileTypeLabelFrame.origin.y
        = round(iconFrame.origin.y + (iconFrame.size.height - fileTypeLabelFrame.size.height) * 0.5f);
    fileTypeLabel.frame = fileTypeLabelFrame;
    [self addSubview:fileTypeLabel];

    const CGFloat kLabelHSpacing = self.iconHSpacing;
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
    [topLabel sizeToFit];
    [self addSubview:topLabel];

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
    [bottomLabel sizeToFit];
    [self addSubview:bottomLabel];

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
}

@end

NS_ASSUME_NONNULL_END
