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

@property (nonatomic, readonly) TSQuotedMessage *quotedMessage;
@property (nonatomic, nullable, readonly) DisplayableText *displayableQuotedText;

@property (nonatomic, nullable) OWSBubbleStrokeView *boundsStrokeView;

@end

#pragma mark -

@implementation OWSQuotedMessageView

+ (OWSQuotedMessageView *)quotedMessageViewForConversation:(TSQuotedMessage *)quotedMessage
                                     displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
{
    OWSAssert(quotedMessage);

    return
        [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage displayableQuotedText:displayableQuotedText];
}

+ (OWSQuotedMessageView *)quotedMessageViewForPreview:(TSQuotedMessage *)quotedMessage
{
    OWSAssert(quotedMessage);

    DisplayableText *_Nullable displayableQuotedText = nil;
    if (quotedMessage.body.length > 0) {
        displayableQuotedText = [DisplayableText displayableText:quotedMessage.body];
    }

    return
        [[OWSQuotedMessageView alloc] initWithQuotedMessage:quotedMessage displayableQuotedText:displayableQuotedText];
}

- (instancetype)initWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                displayableQuotedText:(nullable DisplayableText *)displayableQuotedText
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(quotedMessage);

    _quotedMessage = quotedMessage;
    _displayableQuotedText = displayableQuotedText;

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
    BOOL isIncomingQuote
        = ![NSObject isNullableObject:self.quotedMessage.authorId equalTo:TSAccountManager.localNumber];
    return (isIncomingQuote ? OWSMessagesBubbleImageFactory.bubbleColorIncoming
                            : OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent);
}

#pragma mark -

- (void)createContents
{
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

        if (quotedAttachmentView) {
        }
    }

    UILabel *quotedAuthorLabel = [self createQuotedAuthorLabel];
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
        [stripeAndTextContainer addSubview:quoteStripView];
        [quoteStripView autoPinHeightToSuperview];
        [quoteStripView autoPinLeadingToSuperviewMargin];
        [quoteStripView autoSetDimension:ALDimensionWidth toSize:self.quotedReplyStripeThickness];
        [quoteStripView setContentHuggingVerticalLow];
        [quoteStripView setContentHuggingHorizontalHigh];
        [quoteStripView setCompressionResistanceHigh];

        // Text.
        UILabel *quotedTextLabel = [self createQuotedTextLabel];
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

- (UILabel *)createQuotedTextLabel
{
    UIColor *textColor = self.quotedTextColor;
    UIFont *font = self.quotedTextFont;
    NSString *text = @"";

    NSString *_Nullable fileTypeForSnippet = [self fileTypeForSnippet];
    NSString *_Nullable sourceFilename = [self.quotedMessage.firstThumbnailAttachment.sourceFilename filterStringForDisplay];

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

    UILabel *quotedTextLabel = [UILabel new];
    quotedTextLabel.numberOfLines = 3;
    quotedTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    quotedTextLabel.text = text;
    quotedTextLabel.textColor = textColor;
    quotedTextLabel.font = font;

    return quotedTextLabel;
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
    } else if ([MIMETypeUtil isImage:contentType] || [MIMETypeUtil isAnimated:contentType]) {
        return NSLocalizedString(
            @"QUOTED_REPLY_TYPE_IMAGE", @"Indicates this message is a quoted reply to an image file.");
    }
    return nil;
}

- (UILabel *)createQuotedAuthorLabel
{
    OWSContactsManager *contactsManager = Environment.current.contactsManager;
    NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.quotedMessage.authorId];
    NSString *quotedAuthorText =
        [NSString stringWithFormat:
                      NSLocalizedString(@"QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                          @"Indicates the author of a quoted message. Embeds {{the author's name or phone number}}."),
                  quotedAuthor];

    UILabel *quotedAuthorLabel = [UILabel new];
    quotedAuthorLabel.text = quotedAuthorText;
    quotedAuthorLabel.font = self.quotedAuthorFont;
    quotedAuthorLabel.textColor = [self quotedAuthorColor];
    quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    quotedAuthorLabel.numberOfLines = 1;
    return quotedAuthorLabel;
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

        UILabel *quotedAuthorLabel = [self createQuotedAuthorLabel];

        CGSize quotedAuthorSize
            = CGSizeCeil([quotedAuthorLabel sizeThatFits:CGSizeMake(maxQuotedAuthorWidth, CGFLOAT_MAX)]);

        quotedAuthorWidth = quotedAuthorSize.width;

        result.height += self.quotedAuthorTopInset;
        result.height += self.quotedAuthorHeight;
        result.height += self.quotedAuthorBottomSpacing;
    }

    CGFloat quotedTextWidth = 0.f;
    {
        CGFloat maxQuotedTextWidth
            = (maxWidth - (result.width + self.quotedReplyStripeThickness + self.quotedReplyStripeHSpacing));

        UILabel *quotedTextLabel = [self createQuotedTextLabel];

        CGSize textSize = CGSizeCeil([quotedTextLabel sizeThatFits:CGSizeMake(maxQuotedTextWidth, CGFLOAT_MAX)]);

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
    return [UIFont ows_mediumFontWithSize:11.f];
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
    // Honor dynamic type in the text.
    // TODO: ?
    return [UIFont ows_dynamicTypeBodyFont];
}

- (UIColor *)fileTypeTextColor
{
    return [UIColor colorWithWhite:0.5f alpha:1.f];
}

- (UIFont *)fileTypeFont
{
    UIFontDescriptor *fontD =
        [self.quotedTextFont.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
    UIFont *font = [UIFont fontWithDescriptor:fontD size:0];
    OWSAssert(font);
    return font ?: self.quotedTextFont;
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

// TODO:
- (CGFloat)quotedAuthorBottomSpacing
{
    return 3.f;
}

- (CGFloat)quotedTextBottomInset
{
    return 4.f;
}

- (CGFloat)quotedReplyStripeThickness
{
    return 2.f;
}

- (CGFloat)quotedReplyStripeVExtension
{
    return 8.f;
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
