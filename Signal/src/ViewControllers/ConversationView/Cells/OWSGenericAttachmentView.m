//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSGenericAttachmentView.h"
#import "OWSBezierPathView.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/TSAttachmentStream.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSGenericAttachmentView ()

@property (nonatomic) TSAttachment *attachment;
@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, weak) id<ConversationViewItem> viewItem;
@property (nonatomic) BOOL isIncoming;
@property (nonatomic) UILabel *topLabel;
@property (nonatomic) UILabel *bottomLabel;

@end

#pragma mark -

@implementation OWSGenericAttachmentView

- (instancetype)initWithAttachment:(TSAttachment *)attachment
                        isIncoming:(BOOL)isIncoming
                          viewItem:(id<ConversationViewItem>)viewItem
{
    self = [super init];

    if (self) {
        _attachment = attachment;
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            _attachmentStream = (TSAttachmentStream *)attachment;
        }
        _isIncoming = isIncoming;
        _viewItem = viewItem;
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

    NSString *_Nullable filename = self.attachment.sourceFilename;
    if (!filename) {
        filename = [[self.attachmentStream originalFilePath] lastPathComponent];
    }
    NSString *fileExtension = filename.pathExtension;
    if (fileExtension.length < 1) {
        fileExtension = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType];
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

    [self replaceIconWithDownloadProgressIfNecessary:imageView];

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = [OWSGenericAttachmentView labelVSpacing];
    labelsView.alignment = UIStackViewAlignmentLeading;
    [self addArrangedSubview:labelsView];

    NSString *topText = [self.attachment.sourceFilename ows_stripped];
    if (topText.length < 1) {
        topText = [MIMETypeUtil fileExtensionForMIMEType:self.attachment.contentType].localizedUppercaseString;
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

    unsigned long long fileSize = 0;
    if (self.attachmentStream) {
        NSError *error;
        fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[self.attachmentStream originalFilePath]
                                                                    error:&error]
                       .fileSize;
        OWSAssertDebug(!error);
    }
    // We don't want to show the file size while the attachment is downloading.
    // To avoid layout jitter when the download completes, we reserve space in
    // the layout using a whitespace string.
    NSString *bottomText = @" ";
    if (fileSize > 0) {
        bottomText = [OWSFormat formatFileSize:fileSize];
    }
    UILabel *bottomLabel = [UILabel new];
    self.bottomLabel = bottomLabel;
    bottomLabel.text = bottomText;
    bottomLabel.textColor = [conversationStyle bubbleSecondaryTextColorWithIsIncoming:self.isIncoming];
    bottomLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    bottomLabel.font = [OWSGenericAttachmentView bottomLabelFont];
    [labelsView addArrangedSubview:bottomLabel];
}

- (void)replaceIconWithDownloadProgressIfNecessary:(UIView *)iconView
{
    if (!self.viewItem.attachmentPointer) {
        return;
    }

    switch (self.viewItem.attachmentPointer.state) {
        case TSAttachmentPointerStateFailed:
            // We don't need to handle the "tap to retry" state here,
            // only download progress.
            return;
        case TSAttachmentPointerStateEnqueued:
        case TSAttachmentPointerStateDownloading:
            break;
    }
    switch (self.viewItem.attachmentPointer.pointerType) {
        case TSAttachmentPointerTypeRestoring:
            // TODO: Show "restoring" indicator and possibly progress.
            return;
        case TSAttachmentPointerTypeUnknown:
        case TSAttachmentPointerTypeIncoming:
            break;
    }
    NSString *_Nullable uniqueId = self.viewItem.attachmentPointer.uniqueId;
    if (uniqueId.length < 1) {
        OWSFailDebug(@"Missing uniqueId.");
        return;
    }

    CGSize iconViewSize = [iconView sizeThatFits:CGSizeZero];
    CGFloat downloadViewSize = MIN(iconViewSize.width, iconViewSize.height);
    MediaDownloadView *downloadView =
        [[MediaDownloadView alloc] initWithAttachmentId:uniqueId radius:downloadViewSize * 0.5f];
    iconView.layer.opacity = 0.01f;
    [self addSubview:downloadView];
    [downloadView autoSetDimensionsToSize:CGSizeMake(downloadViewSize, downloadViewSize)];
    [downloadView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:iconView];
    [downloadView autoAlignAxis:ALAxisVertical toSameAxisOfView:iconView];
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
