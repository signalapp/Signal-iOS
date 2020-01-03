//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHeaderView.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSUnreadIndicatorInteraction;

const CGFloat OWSMessageHeaderViewStrokeThickness = 1;

@interface OWSMessageHeaderView ()

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIView *strokeView;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;
@property (nonatomic) UIStackView *stackView;

@end

#pragma mark -

@implementation OWSMessageHeaderView

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
    OWSAssertDebug(!self.titleLabel);

    self.layoutMargins = UIEdgeInsetsZero;
    self.layoutConstraints = @[];

    // Intercept touches.
    // Date breaks and unread indicators are not interactive.
    self.userInteractionEnabled = YES;

    self.strokeView = [UIView new];
    [self.strokeView setContentHuggingHigh];

    self.titleLabel = [UILabel new];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.strokeView, self.titleLabel ]];
    self.stackView.axis = NSTextLayoutOrientationVertical;
    self.stackView.spacing = 2;
    [self addSubview:self.stackView];
}

- (void)loadForDisplayWithViewItem:(id<ConversationViewItem>)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(viewItem);
    OWSAssertDebug(conversationStyle);
    OWSAssertDebug(viewItem.shouldShowDate);

    self.titleLabel.textColor = Theme.primaryTextColor;

    [self configureLabelsWithViewItem:viewItem];

    self.strokeView.layer.cornerRadius = OWSMessageHeaderViewStrokeThickness * 0.5f;
    self.strokeView.backgroundColor = Theme.secondaryTextAndIconColor;

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.strokeView autoSetDimension:ALDimensionHeight toSize:OWSMessageHeaderViewStrokeThickness],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:conversationStyle.headerGutterLeading],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:conversationStyle.headerGutterTrailing]
    ];
}

- (void)configureLabelsWithViewItem:(id<ConversationViewItem>)viewItem
{
    OWSAssertDebug(viewItem);

    NSDate *date = viewItem.interaction.receivedAtDate;
    NSString *dateString = [DateUtil formatDateForConversationDateBreaks:date].localizedUppercaseString;

    self.titleLabel.font = UIFont.ows_dynamicTypeBody2Font;
    self.titleLabel.text = dateString;
}

- (CGSize)measureWithConversationViewItem:(id<ConversationViewItem>)viewItem
                        conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertDebug(viewItem);
    OWSAssertDebug(conversationStyle);
    OWSAssertDebug(viewItem.shouldShowDate);

    [self configureLabelsWithViewItem:viewItem];

    CGSize result = CGSizeMake(conversationStyle.viewWidth, 0);

    result.height += OWSMessageHeaderViewStrokeThickness;

    CGFloat maxTextWidth = conversationStyle.headerViewContentWidth;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
    result.height += titleSize.height + self.stackView.spacing;

    result.height += conversationStyle.headerViewDateHeaderVMargin;

    return CGSizeCeil(result);
}

@end

NS_ASSUME_NONNULL_END
