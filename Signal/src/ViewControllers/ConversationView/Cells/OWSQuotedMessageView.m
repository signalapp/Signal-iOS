//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSQuotedMessageView.h"
#import "ConversationViewItem.h"
#import "Environment.h"
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

@property (nonatomic, readonly) ConversationViewItem *viewItem;
@property (nonatomic, readonly) UIFont *textMessageFont;

@end

@implementation OWSQuotedMessageView

- (instancetype)initWithViewItem:(ConversationViewItem *)viewItem
                 //                   quotedMessage:(TSQuotedMessage *)quotedMessage
                 textMessageFont:(UIFont *)textMessageFont
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(viewItem);
    //    OWSAssert(quotedMessage);
    OWSAssert(textMessageFont);

    _viewItem = viewItem;
    //    _quotedMessage = quotedMessage;
    _textMessageFont = textMessageFont;

    return self;
}

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)hasQuotedAttachmentThumbnail
{
    // This should always be valid for the appropriate cell types.
    OWSAssert(self.viewItem);

    return (self.viewItem.hasQuotedAttachment &&
        [TSAttachmentStream hasThumbnailForMimeType:self.viewItem.quotedAttachmentMimetype]);
}

#pragma mark -

- (void)createContents
{
    OWSAssert(self.viewItem.isQuotedReply);

    self.backgroundColor = [UIColor whiteColor];
    self.userInteractionEnabled = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.clipsToBounds = YES;

    UIView *_Nullable quotedAttachmentView = nil;
    // TODO:
    //    if (self.hasQuotedAttachmentThumbnail)
    {
        // TODO:
        quotedAttachmentView = [UIView containerView];
        quotedAttachmentView.userInteractionEnabled = NO;
        quotedAttachmentView.backgroundColor = [UIColor redColor];
        [self addSubview:quotedAttachmentView];
        [quotedAttachmentView autoPinTrailingToSuperviewMarginWithInset:self.quotedContentHInset];
        [quotedAttachmentView autoVCenterInSuperview];
        [quotedAttachmentView autoSetDimension:ALDimensionWidth toSize:self.quotedAttachmentSize];
        [quotedAttachmentView autoSetDimension:ALDimensionHeight toSize:self.quotedAttachmentSize];
        [quotedAttachmentView setContentHuggingHigh];
        [quotedAttachmentView setCompressionResistanceHigh];

        // TODO: Consider stroking the quoted thumbnail.
    }

    OWSContactsManager *contactsManager = Environment.current.contactsManager;
    NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.viewItem.quotedRecipientId];

    UILabel *quotedAuthorLabel = [UILabel new];
    {
        quotedAuthorLabel.text = quotedAuthor;
        quotedAuthorLabel.font = self.quotedAuthorFont;
        quotedAuthorLabel.textColor
            = (self.isIncoming ? [UIColor colorWithRGBHex:0xd84315] : [UIColor colorWithRGBHex:0x007884]);
        quotedAuthorLabel.numberOfLines = 1;
        quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
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
        [stripeAndTextContainer autoPinBottomToSuperviewMarginWithInset:self.quotedContentHInset];
        [stripeAndTextContainer setContentHuggingLow];
        [stripeAndTextContainer setCompressionResistanceLow];

        // Stripe.
        UIView *quoteStripView = [UIView containerView];
        quoteStripView.backgroundColor = (self.isIncoming ? [UIColor whiteColor] : [UIColor colorWithRGBHex:0x007884]);
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

#pragma mark - Measurement

// TODO: Class method?
- (CGSize)sizeForMaxWidth:(CGFloat)maxWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    CGSize result = CGSizeZero;

    if (!self.viewItem.isQuotedReply) {
        return result;
    }

    result.width += self.quotedContentHInset;

    CGFloat thumbnailHeight = 0.f;
    if (self.hasQuotedAttachmentThumbnail) {
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

        OWSContactsManager *contactsManager = Environment.current.contactsManager;
        NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.viewItem.quotedRecipientId];

        UILabel *quotedAuthorLabel = [UILabel new];
        quotedAuthorLabel.text = quotedAuthor;
        quotedAuthorLabel.font = self.quotedAuthorFont;
        quotedAuthorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        quotedAuthorLabel.numberOfLines = 1;

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
        result.height += self.quotedAuthorBottomSpacing;
        result.height += textSize.height + self.quotedReplyStripeVExtension * 2;
    }

    CGFloat textWidth = MAX(quotedAuthorWidth, quotedTextWidth);
    result.width += textWidth;

    result.height += self.quotedTextBottomInset;
    result.height = MAX(result.height, thumbnailHeight);

    return result;
}

- (UILabel *)createQuotedTextLabel
{
    UILabel *quotedTextLabel = [UILabel new];
    quotedTextLabel.numberOfLines = 3;
    quotedTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    quotedTextLabel.text = self.quotedSnippet;
    quotedTextLabel.textColor = self.quotedTextColor;

    // Honor dynamic type in the message bodies.
    quotedTextLabel.font = self.textMessageFont;
    return quotedTextLabel;
}

- (UIColor *)quotedTextColor
{
    return [UIColor blackColor];
}

- (NSString *)quotedSnippet
{
    if (self.viewItem.hasQuotedText && self.viewItem.displayableQuotedText.displayText.length > 0) {
        return self.viewItem.displayableQuotedText.displayText;
    } else {
        NSString *mimeType = self.viewItem.quotedAttachmentMimetype;

        if (mimeType.length > 0) {
            return [TSAttachment emojiForMimeType:mimeType];
        }
    }

    return @"";
}

// TODO:
- (UIFont *)quotedAuthorFont
{
    return [UIFont ows_regularFontWithSize:10.f];
}

// TODO:
- (CGFloat)quotedAuthorHeight
{
    return (CGFloat)ceil([self quotedAuthorFont].lineHeight * 1.f);
}

// TODO:
- (CGFloat)quotedAuthorTopInset
{
    return 4.f;
}

// TODO:
- (CGFloat)quotedAuthorBottomSpacing
{
    return 2.f;
}

// TODO:
- (CGFloat)quotedTextBottomInset
{
    return 5.f;
}

// TODO:
- (CGFloat)quotedReplyStripeThickness
{
    return 3.f;
}

// TODO:
- (CGFloat)quotedReplyStripeVExtension
{
    return 5.f;
}

// The spacing between the vertical "quoted reply stripe"
// and the quoted message content.
// TODO:
- (CGFloat)quotedReplyStripeHSpacing
{
    return 8.f;
}

// Distance from top edge of "quoted message" bubble to top of message bubble.
// TODO:
- (CGFloat)quotedAttachmentMinVInset
{
    return 10.f;
}

// TODO:
- (CGFloat)quotedAttachmentSize
{
    return 30.f;
}

// TODO:
- (CGFloat)quotedAttachmentHSpacing
{
    return 10.f;
}

// Distance from sides of the quoted content to the sides of the message bubble.
// TODO:
- (CGFloat)quotedContentHInset
{
    return 8.f;
}

@end

NS_ASSUME_NONNULL_END
