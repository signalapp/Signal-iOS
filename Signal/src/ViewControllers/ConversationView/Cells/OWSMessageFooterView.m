//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageFooterView.h"
#import "DateUtil.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageFooterView ()

@property (nonatomic) UILabel *timestampLabel;
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

    self.timestampLabel = [UILabel new];
    // TODO: Color
    self.timestampLabel.textColor = [UIColor lightGrayColor];
    [self addSubview:self.timestampLabel];

    self.statusLabel = [UILabel new];
    // TODO: Color
    self.statusLabel.textColor = [UIColor lightGrayColor];

    self.statusIndicatorView = [UIView new];
    [self.statusIndicatorView autoSetDimension:ALDimensionWidth toSize:self.statusIndicatorSize];
    [self.statusIndicatorView autoSetDimension:ALDimensionHeight toSize:self.statusIndicatorSize];
    self.statusIndicatorView.layer.cornerRadius = self.statusIndicatorSize * 0.5f;

    // TODO: Review constant with Myles.0
    UIStackView *statusStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.statusLabel,
        self.statusIndicatorView,
    ]];
    statusStackView.axis = UILayoutConstraintAxisHorizontal;
    statusStackView.spacing = self.hSpacing;
    [self addSubview:statusStackView];

    [self.timestampLabel autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [statusStackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.timestampLabel autoVCenterInSuperview];
    [statusStackView autoVCenterInSuperview];
    [self.timestampLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [self.timestampLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom
                                          withInset:0
                                           relation:NSLayoutRelationGreaterThanOrEqual];
    [statusStackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [statusStackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [statusStackView autoPinEdge:ALEdgeLeading
                          toEdge:ALEdgeTrailing
                          ofView:self.timestampLabel
                      withOffset:self.hSpacing
                        relation:NSLayoutRelationGreaterThanOrEqual];
}

- (void)configureFonts
{
    self.timestampLabel.font = UIFont.ows_dynamicTypeCaption2Font;
    self.statusLabel.font = UIFont.ows_dynamicTypeCaption2Font;
}

- (CGFloat)statusIndicatorSize
{
    // TODO: Review constant.
    return 20.f;
}

- (CGFloat)hSpacing
{
    // TODO: Review constant.
    return 10.f;
}

#pragma mark - Load

- (void)configureWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];
    ;

    // TODO:
    self.statusIndicatorView.backgroundColor = [UIColor ows_materialBlueColor];
}

- (void)configureLabelsWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureFonts];

    // TODO: Correct text.
    self.timestampLabel.text =
        [DateUtil formatPastTimestampRelativeToNow:viewItem.interaction.timestamp isRTL:CurrentAppContext().isRTL];
    self.statusLabel.text = [self messageStatusTextForConversationViewItem:viewItem];
}

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    [self configureLabelsWithConversationViewItem:viewItem];
    ;

    CGSize result = CGSizeZero;
    result.height
        = MAX(self.timestampLabel.font.lineHeight, MAX(self.statusLabel.font.lineHeight, self.statusIndicatorSize));
    result.width = ([self.timestampLabel sizeThatFits:CGSizeZero].width +
        [self.statusLabel sizeThatFits:CGSizeZero].width + self.statusIndicatorSize + self.hSpacing * 2.f);
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
