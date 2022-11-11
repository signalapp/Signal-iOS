//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSQuotedMessageView.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kRemotelySourcedContentGlyphLength = 16;
const CGFloat kRemotelySourcedContentRowMargin = 4;
const CGFloat kRemotelySourcedContentRowSpacing = 3;

@interface OWSQuotedMessageView ()

@property (nonatomic, readonly) OWSQuotedReplyModel *quotedMessage;
@property (nonatomic, nullable, readonly) DisplayableText *displayableQuotedText;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, readonly) UILabel *quotedAuthorLabel;
@property (nonatomic, readonly) UILabel *quotedTextLabel;
@property (nonatomic, readonly) UILabel *quoteContentSourceLabel;

@end

#pragma mark -

@implementation OWSQuotedMessageView

+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(OWSQuotedReplyModel *)quotedMessage
                                    conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(quotedMessage);

    DisplayableText *_Nullable displayableQuotedText = nil;
    if (quotedMessage.body.length > 0) {
        __block DisplayableText *displayableText;
        [SDSDatabaseStorage.shared readWithBlock:^(SDSAnyReadTransaction *transaction) {
            displayableText = [DisplayableText
                displayableTextWithMessageBody:[[MessageBody alloc]
                                                   initWithText:quotedMessage.body
                                                         ranges:quotedMessage.bodyRanges ?: MessageBodyRanges.empty]
                                  mentionStyle:MentionStyleQuotedReply
                                   transaction:transaction];
        }];
        displayableQuotedText = displayableText;
    }

    OWSQuotedMessageView *instance = [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage
                                                                   displayableQuotedText:displayableQuotedText
                                                                       conversationStyle:conversationStyle];
    [instance createContents];
    return instance;
}

- (instancetype)initWithQuotedMessage:(OWSQuotedReplyModel *)quotedMessage
                displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                    conversationStyle:(ConversationStyle *)conversationStyle
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(quotedMessage);

    _quotedMessage = quotedMessage;
    _displayableQuotedText = displayableQuotedText;
    _conversationStyle = conversationStyle;

    _quotedAuthorLabel = [UILabel new];
    _quotedTextLabel = [UILabel new];
    _quoteContentSourceLabel = [UILabel new];

    return self;
}

- (BOOL)hasQuotedAttachment
{
    if (self.quotedMessage.contentType.length > 0
        && ![OWSMimeTypeOversizeTextMessage isEqualToString:self.quotedMessage.contentType]) {
        return YES;
    }
    if (self.quotedMessage.isGiftBadge) {
        return YES;
    }
    return NO;
}

- (BOOL)hasQuotedAttachmentThumbnailImage
{
    return (self.quotedMessage.contentType.length > 0
        && ![OWSMimeTypeOversizeTextMessage isEqualToString:self.quotedMessage.contentType] &&
        [TSAttachmentStream hasThumbnailForMimeType:self.quotedMessage.contentType]);
}

- (UIColor *)highlightColor
{
    return [self.conversationStyle quotedReplyHighlightColor];
}

#pragma mark -

- (CGFloat)bubbleHMargin
{
    return 0.f;
}

- (CGFloat)hSpacing
{
    return 8.f;
}

- (CGFloat)vSpacing
{
    return 2.f;
}

- (CGFloat)stripeThickness
{
    return 4.f;
}

- (void)createContents
{
    // Ensure only called once.
    OWSAssertDebug(self.subviews.count < 1);

    self.userInteractionEnabled = YES;
    self.layoutMargins = UIEdgeInsetsZero;
    self.clipsToBounds = YES;

    CAShapeLayer *maskLayer = [CAShapeLayer new];
    UIRectCorner sharpCorners = [UIView uiRectCornerForOWSDirectionalRectCorner:OWSDirectionalRectCornerBottomLeading |
                                        OWSDirectionalRectCornerBottomTrailing];

    OWSLayerView *innerBubbleView = [[OWSLayerView alloc]
         initWithFrame:CGRectZero
        layoutCallback:^(UIView *layerView) {
            const CGFloat sharpCornerRadius = 4;
            const CGFloat wideCornerRadius = 12;
            UIBezierPath *bezierPath = [UIBezierPath roundedRect:layerView.bounds
                                                    sharpCorners:sharpCorners
                                               sharpCornerRadius:sharpCornerRadius
                                                wideCornerRadius:wideCornerRadius];
            maskLayer.path = bezierPath.CGPath;
        }];
    innerBubbleView.layer.mask = maskLayer;

    // Background
    CVColorOrGradientView *chatColorView = [CVColorOrGradientView buildWithConversationStyle:self.conversationStyle
                                                                               referenceView:self];
    chatColorView.shouldDeactivateConstraints = NO;
    [innerBubbleView addSubview:chatColorView];
    [chatColorView autoPinEdgesToSuperviewEdges];
    UIView *tintView = [UIView new];
    tintView.backgroundColor = (self.conversationStyle.isDarkThemeEnabled ? [UIColor colorWithWhite:0 alpha:0.4]
                                                                          : [UIColor colorWithWhite:1 alpha:0.6]);
    [innerBubbleView addSubview:tintView];
    [tintView autoPinEdgesToSuperviewEdges];

    [self addSubview:innerBubbleView];
    [innerBubbleView autoPinLeadingToSuperviewMarginWithInset:self.bubbleHMargin];
    [innerBubbleView autoPinTrailingToSuperviewMarginWithInset:self.bubbleHMargin];
    [innerBubbleView autoPinTopToSuperviewMargin];
    [innerBubbleView autoPinBottomToSuperviewMargin];
    [innerBubbleView setContentHuggingHorizontalLow];
    [innerBubbleView setCompressionResistanceHorizontalLow];

    UIStackView *hStackView = [UIStackView new];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = self.hSpacing;

    UIView *stripeView = [UIView new];
    stripeView.backgroundColor = UIColor.ows_whiteColor;
    [stripeView autoSetDimension:ALDimensionWidth toSize:self.stripeThickness];
    [stripeView setContentHuggingHigh];
    [stripeView setCompressionResistanceHigh];
    [hStackView addArrangedSubview:stripeView];

    UIStackView *vStackView = [UIStackView new];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.layoutMargins = UIEdgeInsetsMake(self.textVMargin, 0, self.textVMargin, 0);
    vStackView.layoutMarginsRelativeArrangement = YES;
    vStackView.spacing = self.vSpacing;
    [vStackView setContentHuggingHorizontalLow];
    [vStackView setCompressionResistanceHorizontalLow];
    [hStackView addArrangedSubview:vStackView];

    UILabel *quotedAuthorLabel = [self configureQuotedAuthorLabel];
    [vStackView addArrangedSubview:quotedAuthorLabel];
    [quotedAuthorLabel autoSetDimension:ALDimensionHeight toSize:self.quotedAuthorHeight];
    [quotedAuthorLabel setContentHuggingVerticalHigh];
    [quotedAuthorLabel setContentHuggingHorizontalLow];
    [quotedAuthorLabel setCompressionResistanceHorizontalLow];

    UILabel *quotedTextLabel = [self configureQuotedTextLabel];
    [vStackView addArrangedSubview:quotedTextLabel];
    [quotedTextLabel setContentHuggingHorizontalLow];
    [quotedTextLabel setCompressionResistanceHorizontalLow];
    [quotedTextLabel setCompressionResistanceVerticalHigh];

    if (self.hasQuotedAttachment) {
        UIView *_Nullable quotedAttachmentView = nil;
        UIImage *_Nullable thumbnailImage = [self tryToLoadThumbnailImage];
        if (thumbnailImage) {
            quotedAttachmentView = [self imageViewForImage:thumbnailImage];
            quotedAttachmentView.clipsToBounds = YES;

            if (self.isVideoAttachment) {
                UIImage *contentIcon = [UIImage imageNamed:@"attachment_play_button"];
                contentIcon = [contentIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                UIImageView *contentImageView = [self imageViewForImage:contentIcon];
                contentImageView.tintColor = [UIColor whiteColor];
                [quotedAttachmentView addSubview:contentImageView];
                [contentImageView autoCenterInSuperview];
            }
        } else if (self.quotedMessage.failedThumbnailAttachmentPointer) {
            // TODO design review icon and color
            UIImage *contentIcon =
                [[UIImage imageNamed:@"btnRefresh--white"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIImageView *contentImageView = [self imageViewForImage:contentIcon];
            contentImageView.contentMode = UIViewContentModeScaleAspectFit;
            contentImageView.tintColor = UIColor.whiteColor;

            quotedAttachmentView = [UIView containerView];
            [quotedAttachmentView addSubview:contentImageView];
            quotedAttachmentView.backgroundColor = self.highlightColor;
            [contentImageView autoCenterInSuperview];
            [contentImageView
                autoSetDimensionsToSize:CGSizeMake(self.quotedAttachmentSize * 0.5f, self.quotedAttachmentSize * 0.5f)];

            UITapGestureRecognizer *tapGesture =
                [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapFailedThumbnailDownload:)];
            [quotedAttachmentView addGestureRecognizer:tapGesture];
            quotedAttachmentView.userInteractionEnabled = YES;
        } else if (self.quotedMessage.isGiftBadge) {
            UIImage *giftIcon = [UIImage imageNamed:@"gift-thumbnail"];
            UIImageView *contentImageView = [self imageViewForImage:giftIcon];
            contentImageView.contentMode = UIViewContentModeScaleAspectFit;

            UIView *wrapper = [UIView transparentContainer];
            [wrapper addSubview:contentImageView];
            [contentImageView autoCenterInSuperview];
            [contentImageView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize];
            quotedAttachmentView = wrapper;
        } else {
            // TODO: Should we overlay the file extension like we do with CVComponentGenericAttachment
            UIImage *contentIcon = [UIImage imageNamed:@"generic-attachment"];
            UIImageView *contentImageView = [self imageViewForImage:contentIcon];
            contentImageView.contentMode = UIViewContentModeScaleAspectFit;

            UIView *wrapper = [UIView transparentContainer];
            [wrapper addSubview:contentImageView];
            [contentImageView autoCenterInSuperview];
            [contentImageView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize * 0.5f];
            quotedAttachmentView = wrapper;
        }

        [quotedAttachmentView autoPinToSquareAspectRatio];
        [quotedAttachmentView setContentHuggingHigh];
        [quotedAttachmentView setCompressionResistanceHigh];
        [hStackView addArrangedSubview:quotedAttachmentView];
    } else {
        // If there's no attachment, add an empty view so that
        // the stack view's spacing serves as a margin between
        // the text views and the trailing edge.
        UIView *emptyView = [UIView transparentContainer];
        [hStackView addArrangedSubview:emptyView];
        [emptyView setContentHuggingHigh];
        [emptyView autoSetDimension:ALDimensionWidth toSize:0.f];
    }

    UIView *contentView = hStackView;
    [contentView setContentHuggingHorizontalLow];
    [contentView setCompressionResistanceHorizontalLow];

    if (self.quotedMessage.isRemotelySourced) {
        UIStackView *quoteSourceWrapper = [[UIStackView alloc] initWithArrangedSubviews:@[
            contentView,
            [self buildRemoteContentSourceView],
        ]];
        quoteSourceWrapper.axis = UILayoutConstraintAxisVertical;
        contentView = quoteSourceWrapper;
        [contentView setContentHuggingHorizontalLow];
        [contentView setCompressionResistanceHorizontalLow];
    }

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancelButton
        setImage:[[UIImage imageNamed:@"compose-cancel"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
        forState:UIControlStateNormal];
    cancelButton.imageView.tintColor = Theme.secondaryTextAndIconColor;
    [cancelButton addTarget:self action:@selector(didTapCancel) forControlEvents:UIControlEventTouchUpInside];
    [cancelButton setContentHuggingHorizontalHigh];
    [cancelButton setCompressionResistanceHorizontalHigh];

    UIStackView *cancelStack = [[UIStackView alloc] initWithArrangedSubviews:@[ cancelButton ]];
    cancelStack.axis = UILayoutConstraintAxisHorizontal;
    cancelStack.alignment = UIStackViewAlignmentTop;
    cancelStack.layoutMarginsRelativeArrangement = YES;
    CGFloat hMarginLeading = 0;
    CGFloat hMarginTrailing = 6;
    cancelStack.layoutMargins = UIEdgeInsetsMake(6,
        CurrentAppContext().isRTL ? hMarginTrailing : hMarginLeading,
        0,
        CurrentAppContext().isRTL ? hMarginLeading : hMarginTrailing);
    [cancelStack setContentHuggingHorizontalHigh];
    [cancelStack setCompressionResistanceHorizontalHigh];

    UIStackView *cancelWrapper = [[UIStackView alloc] initWithArrangedSubviews:@[
        contentView,
        cancelStack,
    ]];
    cancelWrapper.axis = UILayoutConstraintAxisHorizontal;

    contentView = cancelWrapper;
    [contentView setContentHuggingHorizontalLow];
    [contentView setCompressionResistanceHorizontalLow];

    [innerBubbleView addSubview:contentView];
    [contentView autoPinEdgesToSuperviewEdges];
}

- (UIView *)buildRemoteContentSourceView
{
    UIImage *glyphImage =
        [[UIImage imageNamed:@"ic_broken_link"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssertDebug(glyphImage);
    OWSAssertDebug(CGSizeEqualToSize(
        CGSizeMake(kRemotelySourcedContentGlyphLength, kRemotelySourcedContentGlyphLength), glyphImage.size));
    UIImageView *glyphView = [[UIImageView alloc] initWithImage:glyphImage];
    glyphView.tintColor = Theme.lightThemePrimaryColor;
    [glyphView
        autoSetDimensionsToSize:CGSizeMake(kRemotelySourcedContentGlyphLength, kRemotelySourcedContentGlyphLength)];

    UILabel *label = [self configureQuoteContentSourceLabel];
    UIStackView *sourceRow = [[UIStackView alloc] initWithArrangedSubviews:@[ glyphView, label ]];
    sourceRow.axis = UILayoutConstraintAxisHorizontal;
    sourceRow.alignment = UIStackViewAlignmentCenter;
    // TODO verify spacing w/ design
    sourceRow.spacing = kRemotelySourcedContentRowSpacing;
    sourceRow.layoutMarginsRelativeArrangement = YES;

    const CGFloat leftMargin = 8;
    sourceRow.layoutMargins = UIEdgeInsetsMake(kRemotelySourcedContentRowMargin,
        leftMargin,
        kRemotelySourcedContentRowMargin,
        kRemotelySourcedContentRowMargin);

    UIColor *backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.4];
    [sourceRow addBackgroundViewWithBackgroundColor:backgroundColor];

    return sourceRow;
}

- (void)didTapFailedThumbnailDownload:(UITapGestureRecognizer *)gestureRecognizer
{
    OWSLogDebug(@"in didTapFailedThumbnailDownload");

    if (!self.quotedMessage.failedThumbnailAttachmentPointer) {
        OWSFailDebug(@"thumbnailAttachmentPointer was unexpectedly nil");
        return;
    }

    [self.delegate didTapQuotedReply:self.quotedMessage
        failedThumbnailDownloadAttachmentPointer:self.quotedMessage.failedThumbnailAttachmentPointer];
}

- (nullable UIImage *)tryToLoadThumbnailImage
{
    if (!self.hasQuotedAttachmentThumbnailImage) {
        return nil;
    }

    // TODO: Possibly ignore data that is too large.
    UIImage *_Nullable image = self.quotedMessage.thumbnailImage;
    // TODO: Possibly ignore images that are too large.
    return image;
}

- (UIImageView *)imageViewForImage:(UIImage *)image
{
    OWSAssertDebug(image);

    UIImageView *imageView = [UIImageView new];
    imageView.image = image;
    // We need to specify a contentMode since the size of the image
    // might not match the aspect ratio of the view.
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    // Use trilinear filters for better scaling quality at
    // some performance cost.
    imageView.layer.minificationFilter = kCAFilterTrilinear;
    imageView.layer.magnificationFilter = kCAFilterTrilinear;
    return imageView;
}

- (UILabel *)configureQuotedTextLabel
{
    OWSAssertDebug(self.quotedTextLabel);

    NSAttributedString *attributedText;

    NSString *_Nullable fileTypeForSnippet = [self fileTypeForSnippet];
    NSString *_Nullable sourceFilename = [self.quotedMessage.sourceFilename filterStringForDisplay];

    if (self.displayableQuotedText.displayAttributedText.length > 0) {
        NSMutableAttributedString *mutableText = [self.displayableQuotedText.displayAttributedText mutableCopy];
        [mutableText addAttributes:@{
            NSFontAttributeName : self.quotedTextFont,
            NSForegroundColorAttributeName : self.quotedTextColor
        }
                             range:NSMakeRange(0, mutableText.length)];
        attributedText = mutableText;
    } else if (fileTypeForSnippet) {
        attributedText = [[NSAttributedString alloc] initWithString:fileTypeForSnippet
                                                         attributes:@{
                                                             NSFontAttributeName : self.fileTypeFont,
                                                             NSForegroundColorAttributeName : self.fileTypeTextColor,
                                                         }];
    } else if (sourceFilename) {
        attributedText = [[NSAttributedString alloc] initWithString:sourceFilename
                                                         attributes:@{
                                                             NSFontAttributeName : self.filenameFont,
                                                             NSForegroundColorAttributeName : self.filenameTextColor,
                                                         }];
    } else if (self.quotedMessage.isGiftBadge) {
        attributedText = [[NSAttributedString alloc] initWithString:[self giftTypeForSnippet]
                                                         attributes:@{
                                                             NSFontAttributeName : self.fileTypeFont,
                                                             NSForegroundColorAttributeName : self.fileTypeTextColor,
                                                         }];
    } else {
        attributedText = [[NSAttributedString alloc]
            initWithString:NSLocalizedString(@"QUOTED_REPLY_TYPE_ATTACHMENT",
                               @"Indicates this message is a quoted reply to an attachment of unknown type.")
                attributes:@{
                    NSFontAttributeName : self.fileTypeFont,
                    NSForegroundColorAttributeName : self.fileTypeTextColor,
                }];
    }

    self.quotedTextLabel.numberOfLines = 1;
    self.quotedTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.quotedTextLabel.textAlignment = self.displayableQuotedText.displayTextNaturalAlignment;
    self.quotedTextLabel.attributedText = attributedText;

    return self.quotedTextLabel;
}

- (UILabel *)configureQuoteContentSourceLabel
{
    OWSAssertDebug(self.quoteContentSourceLabel);

    self.quoteContentSourceLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
    self.quoteContentSourceLabel.textColor = Theme.lightThemePrimaryColor;
    self.quoteContentSourceLabel.text = NSLocalizedString(@"QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
        @"Footer label that appears below quoted messages when the quoted content was not derived locally. When the "
        @"local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead "
        @"show the content specified by the sender.");

    return self.quoteContentSourceLabel;
}

- (nullable NSString *)fileTypeForSnippet
{
    // TODO: Are we going to use the filename?  For all mimetypes?
    NSString *_Nullable contentType = self.quotedMessage.contentType;
    if (contentType.length < 1) {
        return nil;
    }

    if ([MIMETypeUtil isAudio:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_AUDIO", @"Indicates this message is a quoted reply to an audio file.");
    } else if ([MIMETypeUtil isAnimated:contentType]) {
        if ([contentType caseInsensitiveCompare:OWSMimeTypeImageGif] == NSOrderedSame) {
            return NSLocalizedString(
                @"QUOTED_REPLY_TYPE_GIF", @"Indicates this message is a quoted reply to animated GIF file.");
        } else {
            return NSLocalizedString(
                @"QUOTED_REPLY_TYPE_IMAGE", @"Indicates this message is a quoted reply to an image file.");
        }
    } else if (self.quotedMessage.attachmentStream.isLoopingVideo) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_GIF", @"Indicates this message is a quoted reply to animated GIF file.");
    } else if ([MIMETypeUtil isVideo:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_VIDEO", @"Indicates this message is a quoted reply to a video file.");
    } else if ([MIMETypeUtil isImage:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_PHOTO", @"Indicates this message is a quoted reply to a photo file.");
    }
    return nil;
}

- (nullable NSString *)giftTypeForSnippet
{
    return NSLocalizedString(
        @"BADGE_GIFTING_REPLY", @"Shown when you're replying to a gift message to indicate that it contains a gift.");
}

- (BOOL)isAudioAttachment
{
    // TODO: Are we going to use the filename?  For all mimetypes?
    NSString *_Nullable contentType = self.quotedMessage.contentType;
    if (contentType.length < 1) {
        return NO;
    }

    return [MIMETypeUtil isAudio:contentType];
}

- (BOOL)isVideoAttachment
{
    // TODO: Are we going to use the filename?  For all mimetypes?
    NSString *_Nullable contentType = self.quotedMessage.contentType;
    if (contentType.length < 1) {
        return NO;
    }

    return [MIMETypeUtil isVideo:contentType];
}

- (UILabel *)configureQuotedAuthorLabel
{
    OWSAssertDebug(self.quotedAuthorLabel);

    NSString *quotedAuthorText;
    if (self.quotedMessage.authorAddress.isLocalAddress) {
        quotedAuthorText = CommonStrings.you;
    } else {
        OWSContactsManager *contactsManager = Environment.shared.contactsManager;
        NSString *quotedAuthor = [contactsManager displayNameForAddress:self.quotedMessage.authorAddress];
        quotedAuthorText = [NSString
            stringWithFormat:
                NSLocalizedString(@"QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                    @"Indicates the author of a quoted message. Embeds {{the author's name or phone number}}."),
            quotedAuthor];
    }

    self.quotedAuthorLabel.text = quotedAuthorText;
    self.quotedAuthorLabel.font = self.quotedAuthorFont;
    // TODO:
    self.quotedAuthorLabel.textColor = [self quotedAuthorColor];
    self.quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.quotedAuthorLabel.numberOfLines = 1;

    return self.quotedAuthorLabel;
}

#pragma mark - Measurement

- (CGFloat)textVMargin
{
    return 7.f;
}

- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth
{
    CGSize result = CGSizeZero;

    result.width += self.bubbleHMargin * 2 + self.stripeThickness + self.hSpacing * 2;

    CGFloat thumbnailHeight = 0.f;
    if (self.hasQuotedAttachment) {
        result.width += self.quotedAttachmentSize;

        thumbnailHeight += self.quotedAttachmentSize;
    }

    // Quoted Author
    CGFloat textWidth = 0.f;
    CGFloat maxTextWidth = maxWidth - result.width;
    CGFloat textHeight = self.textVMargin * 2 + self.quotedAuthorHeight + self.vSpacing;
    {
        UILabel *quotedAuthorLabel = [self configureQuotedAuthorLabel];

        CGSize quotedAuthorSize = CGSizeCeil([quotedAuthorLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
        textWidth = quotedAuthorSize.width;
    }

    {
        UILabel *quotedTextLabel = [self configureQuotedTextLabel];

        CGSize textSize = CGSizeCeil([quotedTextLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
        textWidth = MAX(textWidth, textSize.width);
        textHeight += textSize.height;
    }

    if (self.quotedMessage.isRemotelySourced) {
        UILabel *quoteContentSourceLabel = [self configureQuoteContentSourceLabel];
        CGSize textSize = CGSizeCeil([quoteContentSourceLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)]);
        CGFloat sourceStackViewHeight = MAX(kRemotelySourcedContentGlyphLength, textSize.height);

        textWidth
            = MAX(textWidth, textSize.width + kRemotelySourcedContentGlyphLength + kRemotelySourcedContentRowSpacing);
        result.height += kRemotelySourcedContentRowMargin * 2 + sourceStackViewHeight;
    }

    textWidth = MIN(textWidth, maxTextWidth);
    result.width += textWidth;
    result.height += MAX(textHeight, thumbnailHeight);

    return CGSizeCeil(result);
}

- (UIFont *)quotedAuthorFont
{
    return UIFont.ows_dynamicTypeSubheadlineFont.ows_semibold;
}

- (UIColor *)quotedAuthorColor
{
    return [self.conversationStyle quotedReplyAuthorColor];
}

- (UIColor *)quotedTextColor
{
    return [self.conversationStyle quotedReplyTextColor];
}

- (UIFont *)quotedTextFont
{
    return [UIFont ows_dynamicTypeBodyFont];
}

- (UIColor *)fileTypeTextColor
{
    return [self.conversationStyle quotedReplyAttachmentColor];
}

- (UIFont *)fileTypeFont
{
    return self.quotedTextFont.ows_italic;
}

- (UIColor *)filenameTextColor
{
    return [self.conversationStyle quotedReplyAttachmentColor];
}

- (UIFont *)filenameFont
{
    return self.quotedTextFont;
}

- (CGFloat)quotedAuthorHeight
{
    return (CGFloat)ceil([self quotedAuthorFont].lineHeight * 1.f);
}

- (CGFloat)quotedAttachmentSize
{
    return 54.f;
}

#pragma mark -

- (CGSize)sizeThatFits:(CGSize)size
{
    return [self sizeForMaxWidth:CGFLOAT_MAX];
}

- (void)didTapCancel
{
    [self.delegate didCancelQuotedReply];
}

@end

NS_ASSUME_NONNULL_END
