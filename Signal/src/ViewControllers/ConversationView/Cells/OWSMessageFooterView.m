//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageFooterView.h"
#import "DateUtil.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView ()

@property (nonatomic) UILabel *timestampLabel;
@property (nonatomic) UIImageView *statusIndicatorImageView;

@end

@implementation OWSMessageFooterView

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    // Ensure only called once.
    OWSAssert(!self.timestampLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    self.axis = UILayoutConstraintAxisHorizontal;
    self.spacing = self.hSpacing;
    self.alignment = UIStackViewAlignmentCenter;

    self.timestampLabel = [UILabel new];
    [self addArrangedSubview:self.timestampLabel];

    self.statusIndicatorImageView = [UIImageView new];
    [self.statusIndicatorImageView setContentHuggingHigh];
    [self addArrangedSubview:self.statusIndicatorImageView];
}

- (void)configureFonts
{
    self.timestampLabel.font = UIFont.ows_dynamicTypeCaption1Font;
}

- (CGFloat)hSpacing
{
    // TODO: Review constant.
    return 8.f;
}

- (CGFloat)maxImageWidth
{
    return 18.f;
}

- (CGFloat)imageHeight
{
    return 12.f;
}

#pragma mark - Load

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem isOverlayingMedia:(BOOL)isOverlayingMedia
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];


    // TODO: Constants
    for (UIView *subview in @[
             self.timestampLabel,
             self.statusIndicatorImageView,
         ]) {
        if (isOverlayingMedia) {
            subview.layer.shadowColor = [UIColor blackColor].CGColor;
            subview.layer.shadowOpacity = 0.35f;
            subview.layer.shadowOffset = CGSizeZero;
            subview.layer.shadowRadius = 0.5f;
        } else {
            subview.layer.shadowColor = nil;
            subview.layer.shadowOpacity = 0.f;
            subview.layer.shadowOffset = CGSizeZero;
            subview.layer.shadowRadius = 0.f;
        }
    }

    UIColor *textColor;
    if (isOverlayingMedia) {
        textColor = [UIColor whiteColor];
    } else if (viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage) {
        textColor = [UIColor colorWithWhite:1.f alpha:0.7f];
    } else {
        textColor = [UIColor ows_light60Color];
    }
    self.timestampLabel.textColor = textColor;

    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;

        UIImage *_Nullable statusIndicatorImage = nil;
        MessageReceiptStatus messageStatus =
            [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage referenceView:self];
        switch (messageStatus) {
            case MessageReceiptStatusUploading:
            case MessageReceiptStatusSending:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sending"];
                break;
            case MessageReceiptStatusSent:
            case MessageReceiptStatusSkipped:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sent"];
                break;
            case MessageReceiptStatusDelivered:
            case MessageReceiptStatusRead:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_delivered"];
                break;
            case MessageReceiptStatusFailed:
                // TODO:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sending"];
                break;
        }

        OWSAssert(statusIndicatorImage);
        OWSAssert(statusIndicatorImage.size.width <= self.maxImageWidth);
        self.statusIndicatorImageView.image =
            [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (messageStatus == MessageReceiptStatusRead) {
            // TODO: Tint the icon with the conversation color.
            self.statusIndicatorImageView.tintColor = textColor;
        } else {
            self.statusIndicatorImageView.tintColor = textColor;
        }
        self.statusIndicatorImageView.hidden = NO;
    } else {
        self.statusIndicatorImageView.image = nil;
        self.statusIndicatorImageView.hidden = YES;
    }
}

- (void)configureLabelsWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureFonts];

    self.timestampLabel.text = [DateUtil formatTimestampShort:viewItem.interaction.timestamp];
}

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];

    CGSize result = CGSizeZero;
    result.height = MAX(self.timestampLabel.font.lineHeight, self.imageHeight);
    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        result.width = ([self.timestampLabel sizeThatFits:CGSizeZero].width + self.maxImageWidth + self.hSpacing);
    } else {
        result.width = [self.timestampLabel sizeThatFits:CGSizeZero].width;
    }
    return CGSizeCeil(result);
}

- (nullable NSString *)messageStatusTextForConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);
    if (viewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage) {
        return nil;
    }

    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
    NSString *statusMessage =
        [MessageRecipientStatusUtils receiptMessageWithOutgoingMessage:outgoingMessage referenceView:self];
    return statusMessage;
}

@end

NS_ASSUME_NONNULL_END
