//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSQuotedMessageView.h"
#import "ConversationViewItem.h"
#import "Environment.h"
#import "OWSBubbleView.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kRemotelySourcedContentGlyphLength = 16;
const CGFloat kRemotelySourcedContentRowMargin = 4;
const CGFloat kRemotelySourcedContentRowSpacing = 3;

@interface OWSQuotedMessageView ()

@property (nonatomic, readonly) OWSQuotedReplyModel *quotedMessage;
@property (nonatomic, nullable, readonly) DisplayableText *displayableQuotedText;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, readonly) BOOL isForPreview;
@property (nonatomic, readonly) BOOL isOutgoing;
@property (nonatomic, readonly) OWSDirectionalRectCorner sharpCorners;

@property (nonatomic, readonly) UILabel *quotedAuthorLabel;
@property (nonatomic, readonly) UILabel *quotedTextLabel;
@property (nonatomic, readonly) UILabel *quoteContentSourceLabel;

@end

#pragma mark -

@implementation OWSQuotedMessageView

+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(OWSQuotedReplyModel *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                                         conversationStyle:(ConversationStyle *)conversationStyle
                                                isOutgoing:(BOOL)isOutgoing
                                              sharpCorners:(OWSDirectionalRectCorner)sharpCorners
{
    OWSAssertDebug(quotedMessage);

    return [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage
                                         displayableQuotedText:displayableQuotedText
                                             conversationStyle:conversationStyle
                                                  isForPreview:NO
                                                    isOutgoing:isOutgoing
                                                  sharpCorners:sharpCorners];
}

+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(OWSQuotedReplyModel *)quotedMessage
                                    conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(quotedMessage);

    DisplayableText *_Nullable displayableQuotedText = nil;
    if (quotedMessage.body.length > 0) {
        displayableQuotedText = [DisplayableText displayableText:quotedMessage.body];
    }

    OWSQuotedMessageView *instance =
        [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage
                                      displayableQuotedText:displayableQuotedText
                                          conversationStyle:conversationStyle
                                               isForPreview:YES
                                                 isOutgoing:YES
                                               sharpCorners:OWSDirectionalRectCornerAllCorners];
    [instance createContents];
    return instance;
}

- (instancetype)initWithQuotedMessage:(OWSQuotedReplyModel *)quotedMessage
                displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                    conversationStyle:(ConversationStyle *)conversationStyle
                         isForPreview:(BOOL)isForPreview
                           isOutgoing:(BOOL)isOutgoing
                         sharpCorners:(OWSDirectionalRectCorner)sharpCorners
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(quotedMessage);

    _quotedMessage = quotedMessage;
    _displayableQuotedText = displayableQuotedText;
    _isForPreview = isForPreview;
    _conversationStyle = conversationStyle;
    _isOutgoing = isOutgoing;
    _sharpCorners = sharpCorners;

    _quotedAuthorLabel = [UILabel new];
    _quotedTextLabel = [UILabel new];
    _quoteContentSourceLabel = [UILabel new];

    return self;
}

- (BOOL)hasQuotedAttachment
{
    return (self.quotedMessage.contentType.length > 0
        && ![OWSMimeTypeOversizeTextMessage isEqualToString:self.quotedMessage.contentType]);
}

- (BOOL)hasQuotedAttachmentThumbnailImage
{
    return (self.quotedMessage.contentType.length > 0
        && ![OWSMimeTypeOversizeTextMessage isEqualToString:self.quotedMessage.contentType] &&
        [TSAttachmentStream hasThumbnailForMimeType:self.quotedMessage.contentType]);
}

- (UIColor *)highlightColor
{
    BOOL isQuotingSelf = [NSObject isNullableObject:self.quotedMessage.authorId equalTo:TSAccountManager.localNumber];
    return (isQuotingSelf ? [self.conversationStyle bubbleColorWithIsIncoming:NO]
                          : [self.conversationStyle quotingSelfHighlightColor]);
}

#pragma mark -

- (CGFloat)bubbleHMargin
{
    return 6.f;
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

- (UIColor *)quoteBubbleBackgroundColor
{
    return [self.conversationStyle quotedReplyBubbleColorWithIsIncoming:!self.isOutgoing];
}

- (void)createContents
{
    // Ensure only called once.
    OWSAssertDebug(self.subviews.count < 1);

    self.userInteractionEnabled = YES;
    self.layoutMargins = UIEdgeInsetsZero;
    self.clipsToBounds = YES;

    CAShapeLayer *maskLayer = [CAShapeLayer new];
    OWSDirectionalRectCorner sharpCorners = self.sharpCorners;

    OWSLayerView *innerBubbleView = [[OWSLayerView alloc]
         initWithFrame:CGRectZero
        layoutCallback:^(UIView *layerView) {
            CGRect layerFrame = layerView.bounds;

            const CGFloat bubbleLeft = 0.f;
            const CGFloat bubbleRight = layerFrame.size.width;
            const CGFloat bubbleTop = 0.f;
            const CGFloat bubbleBottom = layerFrame.size.height;

            const CGFloat sharpCornerRadius = 4;
            const CGFloat wideCornerRadius = 12;

            UIBezierPath *bezierPath = [OWSBubbleView roundedBezierRectWithBubbleTop:bubbleTop
                                                                          bubbleLeft:bubbleLeft
                                                                        bubbleBottom:bubbleBottom
                                                                         bubbleRight:bubbleRight
                                                                   sharpCornerRadius:sharpCornerRadius
                                                                    wideCornerRadius:wideCornerRadius
                                                                        sharpCorners:sharpCorners];

            maskLayer.path = bezierPath.CGPath;
        }];
    innerBubbleView.layer.mask = maskLayer;
    innerBubbleView.backgroundColor = self.quoteBubbleBackgroundColor;
    [self addSubview:innerBubbleView];
    [innerBubbleView autoPinLeadingToSuperviewMarginWithInset:self.bubbleHMargin];
    [innerBubbleView autoPinTrailingToSuperviewMarginWithInset:self.bubbleHMargin];
    [innerBubbleView autoPinTopToSuperviewMargin];
    [innerBubbleView autoPinBottomToSuperviewMargin];

    UIStackView *hStackView = [UIStackView new];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = self.hSpacing;

    UIView *stripeView = [UIView new];
    stripeView.backgroundColor = [self.conversationStyle quotedReplyStripeColorWithIsIncoming:!self.isOutgoing];
    [stripeView autoSetDimension:ALDimensionWidth toSize:self.stripeThickness];
    [stripeView setContentHuggingHigh];
    [stripeView setCompressionResistanceHigh];
    [hStackView addArrangedSubview:stripeView];

    UIStackView *vStackView = [UIStackView new];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.layoutMargins = UIEdgeInsetsMake(self.textVMargin, 0, self.textVMargin, 0);
    vStackView.layoutMarginsRelativeArrangement = YES;
    vStackView.spacing = self.vSpacing;
    [hStackView addArrangedSubview:vStackView];

    UILabel *quotedAuthorLabel = [self configureQuotedAuthorLabel];
    [vStackView addArrangedSubview:quotedAuthorLabel];
    [quotedAuthorLabel autoSetDimension:ALDimensionHeight toSize:self.quotedAuthorHeight];
    [quotedAuthorLabel setContentHuggingVerticalHigh];
    [quotedAuthorLabel setContentHuggingHorizontalLow];
    [quotedAuthorLabel setCompressionResistanceHorizontalLow];

    UILabel *quotedTextLabel = [self configureQuotedTextLabel];
    [vStackView addArrangedSubview:quotedTextLabel];
    [quotedTextLabel setContentHuggingLow];
    [quotedTextLabel setCompressionResistanceLow];

    if (self.hasQuotedAttachment) {
        UIView *_Nullable quotedAttachmentView = nil;
        UIImage *_Nullable thumbnailImage = [self tryToLoadThumbnailImage];
        if (thumbnailImage) {
            quotedAttachmentView = [self imageViewForImage:thumbnailImage];
            quotedAttachmentView.clipsToBounds = YES;
            quotedAttachmentView.backgroundColor = [UIColor whiteColor];

            if (self.isVideoAttachment) {
                UIImage *contentIcon = [UIImage imageNamed:@"attachment_play_button"];
                contentIcon = [contentIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                UIImageView *contentImageView = [self imageViewForImage:contentIcon];
                contentImageView.tintColor = [UIColor whiteColor];
                [quotedAttachmentView addSubview:contentImageView];
                [contentImageView autoCenterInSuperview];
            }
        } else if (self.quotedMessage.thumbnailDownloadFailed) {
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
        } else {
            UIImage *contentIcon = [UIImage imageNamed:@"generic-attachment"];
            UIImageView *contentImageView = [self imageViewForImage:contentIcon];
            contentImageView.contentMode = UIViewContentModeScaleAspectFit;

            UIView *wrapper = [UIView containerView];
            [wrapper addSubview:contentImageView];
            [contentImageView autoCenterInSuperview];
            [contentImageView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize * 0.5f];
            quotedAttachmentView = wrapper;
        }

        [quotedAttachmentView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize];
        [quotedAttachmentView setContentHuggingHigh];
        [quotedAttachmentView setCompressionResistanceHigh];
        [hStackView addArrangedSubview:quotedAttachmentView];
    } else {
        // If there's no attachment, add an empty view so that
        // the stack view's spacing serves as a margin between
        // the text views and the trailing edge.
        UIView *emptyView = [UIView containerView];
        [hStackView addArrangedSubview:emptyView];
        [emptyView setContentHuggingHigh];
        [emptyView autoSetDimension:ALDimensionWidth toSize:0.f];
    }

    UIStackView *quoteSourceWrapper = [[UIStackView alloc] initWithArrangedSubviews:@[ hStackView ]];
    quoteSourceWrapper.axis = UILayoutConstraintAxisVertical;

    if (self.quotedMessage.isRemotelySourced) {
        [quoteSourceWrapper addArrangedSubview:[self buildRemoteContentSourceView]];
    }

    [innerBubbleView addSubview:quoteSourceWrapper];
    [quoteSourceWrapper ows_autoPinToSuperviewEdges];
}

- (UIView *)buildRemoteContentSourceView
{
    UIImage *glyphImage =
        [[UIImage imageNamed:@"ic_broken_link"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssertDebug(glyphImage);
    OWSAssertDebug(CGSizeEqualToSize(
        CGSizeMake(kRemotelySourcedContentGlyphLength, kRemotelySourcedContentGlyphLength), glyphImage.size));
    UIImageView *glyphView = [[UIImageView alloc] initWithImage:glyphImage];
    glyphView.tintColor = Theme.secondaryColor;
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

    if (!self.quotedMessage.thumbnailDownloadFailed) {
        OWSFailDebug(@"thumbnailDownloadFailed was unexpectedly false");
        return;
    }

    if (!self.quotedMessage.thumbnailAttachmentPointer) {
        OWSFailDebug(@"thumbnailAttachmentPointer was unexpectedly nil");
        return;
    }

    [self.delegate didTapQuotedReply:self.quotedMessage
        failedThumbnailDownloadAttachmentPointer:self.quotedMessage.thumbnailAttachmentPointer];
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

    UIColor *textColor = self.quotedTextColor;
    SUPPRESS_DEADSTORE_WARNING(textColor);
    UIFont *font = self.quotedTextFont;
    SUPPRESS_DEADSTORE_WARNING(font);
    NSString *text = @"";

    NSString *_Nullable fileTypeForSnippet = [self fileTypeForSnippet];
    NSString *_Nullable sourceFilename = [self.quotedMessage.sourceFilename filterStringForDisplay];

    if (self.displayableQuotedText.displayText.length > 0) {
        text = self.displayableQuotedText.displayText;
        textColor = self.quotedTextColor;
        font = self.quotedTextFont;
    } else if (fileTypeForSnippet) {
        text = fileTypeForSnippet;
        textColor = self.fileTypeTextColor;
        font = self.fileTypeFont;
    } else if (sourceFilename) {
        text = sourceFilename;
        textColor = self.filenameTextColor;
        font = self.filenameFont;
    } else {
        text = NSLocalizedString(
                                 @"QUOTED_REPLY_TYPE_ATTACHMENT", @"Indicates this message is a quoted reply to an attachment of unknown type.");
        textColor = self.fileTypeTextColor;
        font = self.fileTypeFont;
    }

    self.quotedTextLabel.numberOfLines = self.isForPreview ? 1 : 2;
    self.quotedTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.quotedTextLabel.text = text;
    self.quotedTextLabel.textColor = textColor;
    self.quotedTextLabel.font = font;

    return self.quotedTextLabel;
}

- (UILabel *)configureQuoteContentSourceLabel
{
    OWSAssertDebug(self.quoteContentSourceLabel);

    self.quoteContentSourceLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
    self.quoteContentSourceLabel.textColor = Theme.primaryColor;
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
    } else if ([MIMETypeUtil isVideo:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_VIDEO", @"Indicates this message is a quoted reply to a video file.");
    } else if ([MIMETypeUtil isImage:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_IMAGE", @"Indicates this message is a quoted reply to an image file.");
    } else if ([MIMETypeUtil isAnimated:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_GIF", @"Indicates this message is a quoted reply to animated GIF file.");
    }
    return nil;
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

    NSString *_Nullable localNumber = [TSAccountManager localNumber];
    NSString *quotedAuthorText;
    if ([localNumber isEqualToString:self.quotedMessage.authorId]) {

        if (self.isOutgoing) {
            quotedAuthorText = NSLocalizedString(
                @"QUOTED_REPLY_AUTHOR_INDICATOR_YOURSELF", @"message header label when quoting yourself");
        } else {
            quotedAuthorText = NSLocalizedString(
                @"QUOTED_REPLY_AUTHOR_INDICATOR_YOU", @"message header label when someone else is quoting you");
        }
    } else {
        OWSContactsManager *contactsManager = Environment.shared.contactsManager;
        NSString *quotedAuthor = [contactsManager contactOrProfileNameForPhoneIdentifier:self.quotedMessage.authorId];
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
    return UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
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

@end

NS_ASSUME_NONNULL_END
