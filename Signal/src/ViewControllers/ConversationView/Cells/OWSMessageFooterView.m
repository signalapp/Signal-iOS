//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageFooterView.h"
#import "DateUtil.h"
#import "Signal-Swift.h"
#import <QuartzCore/QuartzCore.h>

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

    self.userInteractionEnabled = NO;
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

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem
                        isOverlayingMedia:(BOOL)isOverlayingMedia
                        conversationStyle:(ConversationStyle *)conversationStyle
                               isIncoming:(BOOL)isIncoming
{
    OWSAssert(viewItem);
    OWSAssert(conversationStyle);

    [self configureLabelsWithConversationViewItem:viewItem];

    UIColor *textColor;
    if (isOverlayingMedia) {
        textColor = [UIColor whiteColor];
    } else {
        textColor = [conversationStyle bubbleSecondaryTextColorWithIsIncoming:isIncoming];
    }
    self.timestampLabel.textColor = textColor;

    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;

        UIImage *_Nullable statusIndicatorImage = nil;
        MessageReceiptStatus messageStatus =
            [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
        switch (messageStatus) {
            case MessageReceiptStatusUploading:
            case MessageReceiptStatusSending:
                statusIndicatorImage = [UIImage imageNamed:@"message_status_sending"];
                [self animateSpinningIcon];
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
                // No status indicator icon.
                break;
        }

        if (statusIndicatorImage) {
            OWSAssert(statusIndicatorImage.size.width <= self.maxImageWidth);
            self.statusIndicatorImageView.image =
                [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.statusIndicatorImageView.tintColor = textColor;
            self.statusIndicatorImageView.hidden = NO;
        } else {
            self.statusIndicatorImageView.image = nil;
            self.statusIndicatorImageView.hidden = YES;
        }
    } else {
        self.statusIndicatorImageView.image = nil;
        self.statusIndicatorImageView.hidden = YES;
    }
}

- (void)animateSpinningIcon
{
    CABasicAnimation *animation;
    animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.toValue = @(M_PI * 2.0);
    const CGFloat kPeriodSeconds = 1.f;
    animation.duration = kPeriodSeconds;
    animation.cumulative = YES;
    animation.repeatCount = HUGE_VALF;

    [self.statusIndicatorImageView.layer addAnimation:animation forKey:@"animation"];
}

- (BOOL)isFailedOutgoingMessage:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    if (viewItem.interaction.interactionType != OWSInteractionType_OutgoingMessage) {
        return NO;
    }

    TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
    MessageReceiptStatus messageStatus =
        [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
    return messageStatus == MessageReceiptStatusFailed;
}

- (void)configureLabelsWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureFonts];

    if ([self isFailedOutgoingMessage:viewItem]) {
        self.timestampLabel.text
            = NSLocalizedString(@"MESSAGE_STATUS_SEND_FAILED", @"Label indicating that a message failed to send.");
    } else {
        self.timestampLabel.text = [DateUtil formatTimestampAsTime:viewItem.interaction.timestamp
                                        maxRelativeDurationMinutes:self.maxRelativeDurationMinutes];
    }
}

- (NSInteger)maxRelativeDurationMinutes
{
    return 59;
}

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];

    CGSize result = CGSizeZero;
    result.height = MAX(self.timestampLabel.font.lineHeight, self.imageHeight);

    // Measure the actual current width, to be safe.
    CGFloat timestampLabelWidth = [self.timestampLabel sizeThatFits:CGSizeZero].width;

    // Measuring the timestamp label's width is non-trivial since its
    // contents can be relative the current time.  We avoid having
    // message bubbles' "visually vibrate" as their timestamp labels
    // vary in width.  So we try to leave enough space for all possible
    // contents of this label.
    if ([DateUtil isTimestampRelative:viewItem.interaction.timestamp
            maxRelativeDurationMinutes:self.maxRelativeDurationMinutes]) {
        // Measure the "now" case.
        self.timestampLabel.text = [DateUtil exemplaryNowTimeFormat];
        timestampLabelWidth = MAX(timestampLabelWidth, [self.timestampLabel sizeThatFits:CGSizeZero].width);
        // Measure the "relative time" case.
        // Since this case varies with time, we multiply to leave
        // space for the worst case (whose exact value, due to localization,
        // is unpredictable).
        self.timestampLabel.text =
            [DateUtil exemplaryRelativeTimeFormatWithMaxRelativeDurationMinutes:self.maxRelativeDurationMinutes];
        timestampLabelWidth = MAX(timestampLabelWidth,
            [self.timestampLabel sizeThatFits:CGSizeZero].width + self.timestampLabel.font.lineHeight * 0.5f);

        // Re-configure the labels with the current appropriate value in case
        // we are configuring this view for display.
        [self configureLabelsWithConversationViewItem:viewItem];
    }

    result.width = timestampLabelWidth;
    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        if (![self isFailedOutgoingMessage:viewItem]) {
            result.width += (self.maxImageWidth + self.hSpacing);
        }
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
    NSString *statusMessage = [MessageRecipientStatusUtils receiptMessageWithOutgoingMessage:outgoingMessage];
    return statusMessage;
}

- (void)prepareForReuse
{
    [self.statusIndicatorImageView.layer removeAllAnimations];
}

@end

NS_ASSUME_NONNULL_END
