//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSQuotedMessageView.h"
#import "ConversationViewItem.h"
#import "Environment.h"
#import "OWSBubbleStrokeView.h"
#import "OWSMessageCell.h"
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

@property (nonatomic, readonly) UIFont *textMessageFont;

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
    _textMessageFont = OWSMessageCell.defaultTextMessageFont;

    return self;
}

- (BOOL)hasQuotedAttachment
{
    return (self.quotedMessage.contentType.length > 0
        && ![NSObject isNullableObject:self.quotedMessage.contentType equalTo:OWSMimeTypeOversizeTextMessage]);
}

- (BOOL)hasQuotedAttachmentThumbnail
{
    return (self.quotedMessage.contentType.length > 0
        && ![NSObject isNullableObject:self.quotedMessage.contentType equalTo:OWSMimeTypeOversizeTextMessage] &&
        [TSAttachmentStream hasThumbnailForMimeType:self.quotedMessage.contentType]);
}

- (NSString *)quotedSnippet
{
    if (self.displayableQuotedText.displayText.length > 0) {
        return self.displayableQuotedText.displayText;
    } else {
        NSString *mimeType = self.quotedMessage.contentType;

        if (mimeType.length > 0) {
            return [TSAttachment emojiForMimeType:mimeType];
        }
    }

    return @"";
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
    // TODO:
    if (self.hasQuotedAttachment) {
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
        if (quotedAttachmentView) {
            quotedAttachmentView.layer.borderColor = [UIColor colorWithWhite:0.f alpha:0.1f].CGColor;
            quotedAttachmentView.layer.borderWidth = 1.f;
            quotedAttachmentView.layer.cornerRadius = 2.f;
        }
    }

    OWSContactsManager *contactsManager = Environment.current.contactsManager;
    NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.quotedMessage.authorId];

    UILabel *quotedAuthorLabel = [UILabel new];
    {
        quotedAuthorLabel.text = quotedAuthor;
        quotedAuthorLabel.font = self.quotedAuthorFont;
        // TODO:
        quotedAuthorLabel.textColor = [UIColor ows_darkGrayColor];
        //            = (self.isIncoming ? [UIColor colorWithRGBHex:0xd84315] : [UIColor colorWithRGBHex:0x007884]);
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
        [stripeAndTextContainer autoPinBottomToSuperviewMarginWithInset:self.quotedTextBottomInset];
        [stripeAndTextContainer setContentHuggingLow];
        [stripeAndTextContainer setCompressionResistanceLow];

        // Stripe.
        BOOL isIncomingQuote
            = ![NSObject isNullableObject:self.quotedMessage.authorId equalTo:TSAccountManager.localNumber];
        UIColor *stripeColor = (isIncomingQuote ? OWSMessagesBubbleImageFactory.bubbleColorIncoming
                                                : OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent);
        UIView *quoteStripView = [UIView containerView];
        quoteStripView.backgroundColor = stripeColor;
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

        OWSContactsManager *contactsManager = Environment.current.contactsManager;
        NSString *quotedAuthor = [contactsManager displayNameForPhoneIdentifier:self.quotedMessage.authorId];

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
    return 2.f;
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

#pragma mark -

- (CGSize)sizeThatFits:(CGSize)size
{
    return [self sizeForMaxWidth:CGFLOAT_MAX];
}

@end

NS_ASSUME_NONNULL_END
