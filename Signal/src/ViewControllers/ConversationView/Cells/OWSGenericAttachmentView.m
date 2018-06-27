//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGenericAttachmentView.h"
#import "OWSBezierPathView.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/UIColor+OWS.h>
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

#pragma mark -

- (CGFloat)hMargin
{
    return 0.f;
}

- (CGFloat)hSpacing
{
    return 8.f;
}

+ (CGFloat)vMargin
{
    return 0.f;
}

- (CGFloat)vMargin
{
    return [OWSGenericAttachmentView vMargin];
}

+ (CGFloat)bubbleHeight
{
    CGFloat iconHeight = self.iconHeight;
    CGFloat labelsHeight = ([OWSGenericAttachmentView topLabelFont].lineHeight +
        [OWSGenericAttachmentView bottomLabelFont].lineHeight + [OWSGenericAttachmentView labelVSpacing]);
    CGFloat contentHeight = MAX(iconHeight, labelsHeight);
    return contentHeight + self.vMargin * 2;
}

- (CGFloat)bubbleHeight
{
    return [OWSGenericAttachmentView bubbleHeight];
}

+ (CGFloat)iconHeight
{
    return 48.f;
}

- (CGFloat)iconHeight
{
    return [OWSGenericAttachmentView iconHeight];
}

- (UIColor *)bubbleBackgroundColor
{
    return self.isIncoming ? [UIColor ows_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
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

    self.axis = UILayoutConstraintAxisHorizontal;
    self.alignment = UIStackViewAlignmentCenter;
    self.spacing = self.hSpacing;

    // attachment_file
    UIImage *image = [UIImage imageNamed:@"generic-attachment"];
    OWSAssert(image);
    OWSAssert(image.size.height == self.iconHeight);
    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    imageView.tintColor = self.bubbleBackgroundColor;
    [self addArrangedSubview:imageView];
    [imageView setContentHuggingHigh];

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = [OWSGenericAttachmentView labelVSpacing];
    labelsView.alignment = UIStackViewAlignmentLeading;
    [self addArrangedSubview:labelsView];

    NSString *topText = [self.attachmentStream.sourceFilename ows_stripped];
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
    topLabel.font = [OWSGenericAttachmentView topLabelFont];
    [labelsView addArrangedSubview:topLabel];

    NSError *error;
    unsigned long long fileSize =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[self.attachmentStream filePath] error:&error].fileSize;
    OWSAssert(!error);
    NSString *bottomText = [OWSFormat formatFileSize:fileSize];
    UILabel *bottomLabel = [UILabel new];
    bottomLabel.text = bottomText;
    bottomLabel.textColor = [textColor colorWithAlphaComponent:0.85f];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [OWSGenericAttachmentView bottomLabelFont];
    [labelsView addArrangedSubview:bottomLabel];
}

+ (UIFont *)topLabelFont
{
    return [UIFont ows_dynamicTypeCaption1Font];
}

+ (UIFont *)bottomLabelFont
{
    return [UIFont ows_dynamicTypeCaption2Font];
}

+ (CGFloat)labelVSpacing
{
    return 2.f;
}

@end

NS_ASSUME_NONNULL_END
