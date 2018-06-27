//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageFooterView.h"
#import "DateUtil.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView ()

@property (nonatomic) UILabel *timestampLabel;
@property (nonatomic) UIView *spacerView;
@property (nonatomic) UILabel *statusLabel;
@property (nonatomic) UIView *statusIndicatorView;

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
    // TODO: Color
    self.timestampLabel.textColor = [UIColor lightGrayColor];
    [self addArrangedSubview:self.timestampLabel];

    self.spacerView = [UIView new];
    [self.spacerView setContentHuggingLow];
    [self addArrangedSubview:self.spacerView];

    self.statusLabel = [UILabel new];
    // TODO: Color
    self.statusLabel.textColor = [UIColor lightGrayColor];
    [self addArrangedSubview:self.statusLabel];

    self.statusIndicatorView = [UIView new];
    [self.statusIndicatorView autoSetDimension:ALDimensionWidth toSize:self.statusIndicatorSize];
    [self.statusIndicatorView autoSetDimension:ALDimensionHeight toSize:self.statusIndicatorSize];
    self.statusIndicatorView.layer.cornerRadius = self.statusIndicatorSize * 0.5f;
    [self addArrangedSubview:self.statusIndicatorView];
}

- (void)configureFonts
{
    self.timestampLabel.font = UIFont.ows_dynamicTypeCaption2Font;
    self.statusLabel.font = UIFont.ows_dynamicTypeCaption2Font;
}

- (CGFloat)statusIndicatorSize
{
    // TODO: Review constant.
    return 12.f;
}

- (CGFloat)hSpacing
{
    // TODO: Review constant.
    return 8.f;
}

#pragma mark - Load

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem hasShadows:(BOOL)hasShadows
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];

    // TODO:
    self.statusIndicatorView.backgroundColor = [UIColor orangeColor];

    BOOL isOutgoing = (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage);
    for (UIView *subview in @[
             self.spacerView,
             self.statusLabel,
             self.statusIndicatorView,
         ]) {
        subview.hidden = !isOutgoing;
    }

    [self setHasShadows:hasShadows viewItem:viewItem];
}

- (void)configureLabelsWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureFonts];

    self.timestampLabel.text = [DateUtil formatTimestampShort:viewItem.interaction.timestamp];
    self.statusLabel.text = [self messageStatusTextForConversationViewItem:viewItem];
}

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];

    CGSize result = CGSizeZero;
    result.height
        = MAX(self.timestampLabel.font.lineHeight, MAX(self.statusLabel.font.lineHeight, self.statusIndicatorSize));
    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        result.width = ([self.timestampLabel sizeThatFits:CGSizeZero].width +
            [self.statusLabel sizeThatFits:CGSizeZero].width + self.statusIndicatorSize + self.hSpacing * 3.f);
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

#pragma mark - Shadows

- (void)setHasShadows:(BOOL)hasShadows viewItem:(ConversationViewItem *)viewItem
{
    // TODO: Constants
    for (UIView *subview in @[
             self.timestampLabel,
             self.statusLabel,
             self.statusIndicatorView,
         ]) {
        if (hasShadows) {
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
    if (hasShadows) {
        textColor = [UIColor whiteColor];
    } else if (viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage) {
        // TODO:
        textColor = [UIColor lightGrayColor];
    } else {
        textColor = [UIColor whiteColor];
    }
    self.timestampLabel.textColor = textColor;
    self.statusLabel.textColor = textColor;
}

@end

NS_ASSUME_NONNULL_END
