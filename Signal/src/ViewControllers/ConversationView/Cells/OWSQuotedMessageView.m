//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSQuotedMessageView.h"
#import "ConversationViewItem.h"
#import "Environment.h"
#import "OWSBubbleStrokeView.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSQuotedMessageView ()

@property (nonatomic, readonly) OWSQuotedReplyModel *quotedMessage;
@property (nonatomic, nullable, readonly) DisplayableText *displayableQuotedText;

@property (nonatomic, nullable) OWSBubbleStrokeView *boundsStrokeView;
@property (nonatomic, readonly) BOOL isForPreview;
@property (nonatomic, readonly) BOOL isOutgoing;

@property (nonatomic, readonly) UILabel *quotedAuthorLabel;
@property (nonatomic, readonly) UILabel *quotedTextLabel;

@end

#pragma mark -

@implementation OWSQuotedMessageView

+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(OWSQuotedReplyModel *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                                                isOutgoing:(BOOL)isOutgoing
{
    OWSAssert(quotedMessage);

    return [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage
                                         displayableQuotedText:displayableQuotedText
                                                  isForPreview:NO
                                                    isOutgoing:isOutgoing];
}

+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(OWSQuotedReplyModel *)quotedMessage
{
    OWSAssert(quotedMessage);

    DisplayableText *_Nullable displayableQuotedText = nil;
    if (quotedMessage.body.length > 0) {
        displayableQuotedText = [DisplayableText displayableText:quotedMessage.body];
    }

    OWSQuotedMessageView *instance = [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage
                                                                   displayableQuotedText:displayableQuotedText
                                                                            isForPreview:YES
                                                                              isOutgoing:YES];
    [instance createContents];
    return instance;
}

- (instancetype)initWithQuotedMessage:(OWSQuotedReplyModel *)quotedMessage
                displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
                         isForPreview:(BOOL)isForPreview
                           isOutgoing:(BOOL)isOutgoing
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(quotedMessage);

    _quotedMessage = quotedMessage;
    _displayableQuotedText = displayableQuotedText;
    _isForPreview = isForPreview;
    _isOutgoing = isOutgoing;

    _quotedAuthorLabel = [UILabel new];
    _quotedTextLabel = [UILabel new];

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
    return (isQuotingSelf ? OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent
                          : OWSMessagesBubbleImageFactory.bubbleColorIncoming);
}

#pragma mark -

- (void)createContents
{
    // Ensure only called once.
    OWSAssert(!self.boundsStrokeView);

    self.backgroundColor = [UIColor whiteColor];
    self.userInteractionEnabled = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.clipsToBounds = YES;

    self.boundsStrokeView = [OWSBubbleStrokeView new];
    self.boundsStrokeView.strokeColor = OWSMessagesBubbleImageFactory.bubbleColorIncoming;
    self.boundsStrokeView.strokeThickness = 1.f;
    [self addSubview:self.boundsStrokeView];
    [self.boundsStrokeView autoPinToSuperviewEdges];
    [self.boundsStrokeView setContentHuggingLow];
    [self.boundsStrokeView setCompressionResistanceLow];

    UIView *_Nullable quotedAttachmentView = nil;
    if (self.hasQuotedAttachment) {
        UIImage *_Nullable thumbnailImage = [self tryToLoadThumbnailImage];
        if (thumbnailImage) {
            quotedAttachmentView = [self imageViewForImage:thumbnailImage];

            // Stroke the edge softly.
            quotedAttachmentView.layer.borderColor = [UIColor colorWithWhite:0.f alpha:0.1f].CGColor;
            quotedAttachmentView.layer.borderWidth = 1.f;
            quotedAttachmentView.layer.cornerRadius = 2.f;
            quotedAttachmentView.clipsToBounds = YES;
            quotedAttachmentView.backgroundColor = [UIColor whiteColor];
        } else {
            // TODO: This asset is wrong.
            // TODO: There's a special asset for audio files.
            UIImage *contentIcon = [UIImage imageNamed:@"file-thin-black-filled-large"];
            UIImageView *contentImageView = [self imageViewForImage:contentIcon];
            quotedAttachmentView = [UIView containerView];
            [quotedAttachmentView addSubview:contentImageView];
            quotedAttachmentView.backgroundColor = self.highlightColor;
            quotedAttachmentView.layer.cornerRadius = self.quotedAttachmentSize * 0.5f;
            [contentImageView autoCenterInSuperview];
            [contentImageView
                autoSetDimensionsToSize:CGSizeMake(self.quotedAttachmentSize * 0.5f, self.quotedAttachmentSize * 0.5f)];
        }

        quotedAttachmentView.userInteractionEnabled = NO;
        [self addSubview:quotedAttachmentView];
        [quotedAttachmentView autoPinTrailingToSuperviewMarginWithInset:self.quotedContentHInset];
        [quotedAttachmentView autoVCenterInSuperview];
        [quotedAttachmentView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize];
        [quotedAttachmentView autoSetDimension:ALDimensionHeight toSize:self.quotedAttachmentSize];
        [quotedAttachmentView setContentHuggingHigh];
        [quotedAttachmentView setCompressionResistanceHigh];
    }

    UILabel *quotedAuthorLabel = [self configureQuotedAuthorLabel];
    {
        [self addSubview:quotedAuthorLabel];
        [quotedAuthorLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.quotedAuthorTopInset];
        [quotedAuthorLabel autoPinLeadingToSuperviewMarginWithInset:self.quotedContentHInset];
        if (quotedAttachmentView) {
            [quotedAuthorLabel autoPinTrailingToLeadingEdgeOfView:quotedAttachmentView
                                                           offset:self.quotedAttachmentHSpacing];
        } else {
            [quotedAuthorLabel autoPinTrailingToSuperviewMarginWithInset:self.quotedContentHInset];
        }
        [quotedAuthorLabel autoSetDimension:ALDimensionHeight toSize:self.quotedAuthorHeight];
        [quotedAuthorLabel setContentHuggingLow];
        [quotedAuthorLabel setCompressionResistanceLow];
    }

    {
        // Stripe and text container.
        UIView *stripeAndTextContainer = [UIView containerView];
        [self addSubview:stripeAndTextContainer];
        [stripeAndTextContainer autoPinEdge:ALEdgeTop
                                     toEdge:ALEdgeBottom
                                     ofView:quotedAuthorLabel
                                 withOffset:self.quotedAuthorBottomSpacing];
        [stripeAndTextContainer autoPinLeadingToSuperviewMarginWithInset:self.quotedContentHInset];
        if (quotedAttachmentView) {
            [stripeAndTextContainer autoPinTrailingToLeadingEdgeOfView:quotedAttachmentView
                                                                offset:self.quotedAttachmentHSpacing];
        } else {
            [stripeAndTextContainer autoPinTrailingToSuperviewMarginWithInset:self.quotedContentHInset];
        }
        [stripeAndTextContainer autoPinBottomToSuperviewMarginWithInset:self.quotedTextBottomInset];
        [stripeAndTextContainer setContentHuggingLow];
        [stripeAndTextContainer setCompressionResistanceLow];

        // Stripe.
        UIView *quoteStripView = [UIView containerView];
        quoteStripView.backgroundColor = self.highlightColor;
        quoteStripView.userInteractionEnabled = NO;
        quoteStripView.layer.cornerRadius = self.quotedReplyStripeRounding;
        [stripeAndTextContainer addSubview:quoteStripView];
        [quoteStripView autoPinHeightToSuperview];
        [quoteStripView autoPinLeadingToSuperviewMargin];
        [quoteStripView autoSetDimension:ALDimensionWidth toSize:self.quotedReplyStripeThickness];
        [quoteStripView setContentHuggingVerticalLow];
        [quoteStripView setContentHuggingHorizontalHigh];
        [quoteStripView setCompressionResistanceHigh];

        // Text.
        UILabel *quotedTextLabel = [self configureQuotedTextLabel];
        [stripeAndTextContainer addSubview:quotedTextLabel];
        [quotedTextLabel autoPinTopToSuperviewMarginWithInset:self.quotedReplyStripeVExtension];
        [quotedTextLabel autoPinBottomToSuperviewMarginWithInset:self.quotedReplyStripeVExtension];
        [quotedTextLabel autoPinLeadingToTrailingEdgeOfView:quoteStripView offset:self.quotedReplyStripeHSpacing];
        [quotedTextLabel autoPinTrailingToSuperviewMargin];
        [quotedTextLabel setContentHuggingLow];
        [quotedTextLabel setCompressionResistanceLow];
    }
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
    OWSAssert(image);

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
    OWSAssert(self.quotedTextLabel);

    UIColor *textColor = self.quotedTextColor;
    UIFont *font = self.quotedTextFont;
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

    self.quotedTextLabel.numberOfLines = self.isForPreview ? 1 : 3;
    self.quotedTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.quotedTextLabel.text = text;
    self.quotedTextLabel.textColor = textColor;
    self.quotedTextLabel.font = font;

    return self.quotedTextLabel;
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

- (UILabel *)configureQuotedAuthorLabel
{
    OWSAssert(self.quotedAuthorLabel);

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
        OWSContactsManager *contactsManager = Environment.current.contactsManager;
        NSString *quotedAuthor = [contactsManager contactOrProfileNameForPhoneIdentifier:self.quotedMessage.authorId];
        quotedAuthorText = [NSString
            stringWithFormat:
                NSLocalizedString(@"QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                    @"Indicates the author of a quoted message. Embeds {{the author's name or phone number}}."),
            quotedAuthor];
    }

    self.quotedAuthorLabel.text = quotedAuthorText;
    self.quotedAuthorLabel.font = self.quotedAuthorFont;
    self.quotedAuthorLabel.textColor = [self quotedAuthorColor];
    self.quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.quotedAuthorLabel.numberOfLines = 1;

    return self.quotedAuthorLabel;
}

#pragma mark - Measurement

- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth
{
    CGSize result = CGSizeZero;

    result.width += self.quotedContentHInset;

    CGFloat thumbnailHeight = 0.f;
    if (self.hasQuotedAttachment) {
        result.width += self.quotedAttachmentHSpacing;
        result.width += self.quotedAttachmentSize;

        thumbnailHeight += self.quotedAttachmentMinVInset;
        thumbnailHeight += self.quotedAttachmentSize;
        thumbnailHeight += self.quotedAttachmentMinVInset;
    }

    result.width += self.quotedContentHInset;

    // Quoted Author
    CGFloat quotedAuthorWidth = 0.f;
    {
        CGFloat maxQuotedAuthorWidth = maxWidth - result.width;

        UILabel *quotedAuthorLabel = [self configureQuotedAuthorLabel];

        CGSize quotedAuthorSize
            = CGSizeCeil([quotedAuthorLabel sizeThatFits:CGSizeMake(maxQuotedAuthorWidth, CGFLOAT_MAX)]);
        quotedAuthorSize.width = MIN(quotedAuthorSize.width, maxQuotedAuthorWidth);

        quotedAuthorWidth = quotedAuthorSize.width;

        result.height += self.quotedAuthorTopInset;
        result.height += self.quotedAuthorHeight;
        result.height += self.quotedAuthorBottomSpacing;
    }

    CGFloat quotedTextWidth = 0.f;
    {
        CGFloat maxQuotedTextWidth
            = (maxWidth - (result.width + self.quotedReplyStripeThickness + self.quotedReplyStripeHSpacing));

        UILabel *quotedTextLabel = [self configureQuotedTextLabel];

        CGSize textSize = CGSizeCeil([quotedTextLabel sizeThatFits:CGSizeMake(maxQuotedTextWidth, CGFLOAT_MAX)]);
        textSize.width = MIN(textSize.width, maxQuotedTextWidth);

        quotedTextWidth = textSize.width + self.quotedReplyStripeThickness + self.quotedReplyStripeHSpacing;
        result.height += textSize.height + self.quotedReplyStripeVExtension * 2;
    }

    CGFloat textWidth = MAX(quotedAuthorWidth, quotedTextWidth);
    result.width += textWidth;

    result.height += self.quotedTextBottomInset;
    result.height = MAX(result.height, thumbnailHeight);

    return result;
}

- (UIFont *)quotedAuthorFont
{
    return UIFont.ows_dynamicTypeCaption1Font.ows_medium;
}

- (UIColor *)quotedAuthorColor
{
    return [UIColor colorWithRGBHex:0x8E8E93];
}

- (UIColor *)quotedTextColor
{
    return [UIColor blackColor];
}

- (UIFont *)quotedTextFont
{
    return [UIFont ows_dynamicTypeBodyFont];
}

- (UIColor *)fileTypeTextColor
{
    return [UIColor colorWithWhite:0.5f alpha:1.f];
}

- (UIFont *)fileTypeFont
{
    return self.quotedTextFont.ows_italic;
}

- (UIColor *)filenameTextColor
{
    return [UIColor colorWithWhite:0.5f alpha:1.f];
}

- (UIFont *)filenameFont
{
    return self.quotedTextFont;
}

- (CGFloat)quotedAuthorHeight
{
    return (CGFloat)ceil([self quotedAuthorFont].lineHeight * 1.f);
}

- (CGFloat)quotedAuthorTopInset
{
    return 8.f;
}

- (CGFloat)quotedAuthorBottomSpacing
{
    return 3.f;
}

- (CGFloat)quotedTextBottomInset
{
    return 8.f;
}

- (CGFloat)quotedReplyStripeThickness
{
    return 2.f;
}

- (CGFloat)quotedReplyStripeVExtension
{
    return 4.f;
}

- (CGFloat)quotedReplyStripeRounding
{
    return 1.f;
}

// The spacing between the vertical "quoted reply stripe"
// and the quoted message content.
- (CGFloat)quotedReplyStripeHSpacing
{
    return 4.f;
}

// Distance from top edge of "quoted message" bubble to top of message bubble.
- (CGFloat)quotedAttachmentMinVInset
{
    return 12.f;
}

- (CGFloat)quotedAttachmentSize
{
    return 44.f;
}

- (CGFloat)quotedAttachmentHSpacing
{
    return 8.f;
}

// Distance from sides of the quoted content to the sides of the message bubble.
- (CGFloat)quotedContentHInset
{
    return 8.f;
}

#pragma mark -

- (CGSize)sizeThatFits:(CGSize)size
{
    return [self sizeForMaxWidth:CGFLOAT_MAX];
}

@end

NS_ASSUME_NONNULL_END
