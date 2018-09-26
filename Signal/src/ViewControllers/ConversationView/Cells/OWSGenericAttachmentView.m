//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSGenericAttachmentView.h"
#import "OWSBezierPathView.h"
#import "Signal-Swift.h"
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
@property (nonatomic) UILabel *topLabel;
@property (nonatomic) UILabel *bottomLabel;

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

- (CGFloat)vMargin
{
    return 5.f;
}

- (CGSize)measureSizeWithMaxMessageWidth:(CGFloat)maxMessageWidth
{
    CGSize result = CGSizeZero;

    CGFloat labelsHeight = ([OWSGenericAttachmentView topLabelFont].lineHeight +
        [OWSGenericAttachmentView bottomLabelFont].lineHeight + [OWSGenericAttachmentView labelVSpacing]);
    CGFloat contentHeight = MAX(self.iconHeight, labelsHeight);
    result.height = contentHeight + self.vMargin * 2;

    CGFloat labelsWidth
        = MAX([self.topLabel sizeThatFits:CGSizeZero].width, [self.bottomLabel sizeThatFits:CGSizeZero].width);
    CGFloat contentWidth = (self.iconWidth + labelsWidth + self.hSpacing);
    result.width = MIN(maxMessageWidth, contentWidth + self.hMargin * 2);

    return CGSizeCeil(result);
}

- (CGFloat)iconWidth
{
    return 36.f;
}

- (CGFloat)iconHeight
{
    return kStandardAvatarSize;
}

- (void)createContentsWithConversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(conversationStyle);

    self.axis = UILayoutConstraintAxisHorizontal;
    self.alignment = UIStackViewAlignmentCenter;
    self.spacing = self.hSpacing;
    self.layoutMarginsRelativeArrangement = YES;
    self.layoutMargins = UIEdgeInsetsMake(self.vMargin, 0, self.vMargin, 0);

    // attachment_file
    UIImage *image = [UIImage imageNamed:@"generic-attachment"];
    OWSAssertDebug(image);
    OWSAssertDebug(image.size.width == self.iconWidth);
    OWSAssertDebug(image.size.height == self.iconHeight);
    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    [self addArrangedSubview:imageView];
    [imageView setContentHuggingHigh];

    NSString *filename = self.attachmentStream.sourceFilename;
    if (!filename) {
        filename = [[self.attachmentStream originalFilePath] lastPathComponent];
    }
    NSString *fileExtension = filename.pathExtension;
    if (fileExtension.length < 1) {
        fileExtension = [MIMETypeUtil fileExtensionForMIMEType:self.attachmentStream.contentType];
    }

    UILabel *fileTypeLabel = [UILabel new];
    fileTypeLabel.text = fileExtension.localizedUppercaseString;
    fileTypeLabel.textColor = [UIColor ows_gray90Color];
    fileTypeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    fileTypeLabel.font = [UIFont ows_dynamicTypeCaption1Font].ows_mediumWeight;
    fileTypeLabel.adjustsFontSizeToFitWidth = YES;
    fileTypeLabel.textAlignment = NSTextAlignmentCenter;
    // Center on icon.
    [imageView addSubview:fileTypeLabel];
    [fileTypeLabel autoCenterInSuperview];
    [fileTypeLabel autoSetDimension:ALDimensionWidth toSize:self.iconWidth - 20.f];

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = [OWSGenericAttachmentView labelVSpacing];
    labelsView.alignment = UIStackViewAlignmentLeading;
    [self addArrangedSubview:labelsView];

    NSString *topText = [self.attachmentStream.sourceFilename ows_stripped];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachmentStream.contentType].localizedUppercaseString;
    }
    if (topText.length < 1) {
        topText = NSLocalizedString(@"GENERIC_ATTACHMENT_LABEL", @"A label for generic attachments.");
    }
    UILabel *topLabel = [UILabel new];
    self.topLabel = topLabel;
    topLabel.text = topText;
    topLabel.textColor = [conversationStyle bubbleTextColorWithIsIncoming:self.isIncoming];
    topLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    topLabel.font = [OWSGenericAttachmentView topLabelFont];
    [labelsView addArrangedSubview:topLabel];

    NSError *error;
    unsigned long long fileSize =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[self.attachmentStream originalFilePath] error:&error]
            .fileSize;
    OWSAssertDebug(!error);
    NSString *bottomText = [OWSFormat formatFileSize:fileSize];
    UILabel *bottomLabel = [UILabel new];
    self.bottomLabel = bottomLabel;
    bottomLabel.text = bottomText;
    bottomLabel.textColor = [conversationStyle bubbleSecondaryTextColorWithIsIncoming:self.isIncoming];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [OWSGenericAttachmentView bottomLabelFont];
    [labelsView addArrangedSubview:bottomLabel];
}

+ (UIFont *)topLabelFont
{
    return [UIFont ows_dynamicTypeBodyFont];
}

+ (UIFont *)bottomLabelFont
{
    return [UIFont ows_dynamicTypeCaption1Font];
}

+ (CGFloat)labelVSpacing
{
    return 2.f;
}

@end

NS_ASSUME_NONNULL_END
