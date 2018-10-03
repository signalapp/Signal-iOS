//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHeaderView.h"
#import "ConversationViewItem.h"
#import "Relay-Swift.h"
#import <RelayMessaging/OWSUnreadIndicator.h>
#import <RelayMessaging/UIFont+OWS.h>
#import <RelayMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat OWSMessageHeaderViewDateHeaderVMargin = 23;

@interface OWSMessageHeaderView ()

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *subtitleLabel;
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
    OWSAssert(!self.titleLabel);

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

    self.subtitleLabel = [UILabel new];
    // The subtitle may wrap to a second line.
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;

    self.stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.strokeView,
        self.titleLabel,
        self.subtitleLabel,
    ]];
    self.stackView.axis = NSTextLayoutOrientationVertical;
    self.stackView.spacing = 2;
    [self addSubview:self.stackView];
}

- (void)loadForDisplayWithViewItem:(ConversationViewItem *)viewItem
                 conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssert(viewItem);
    OWSAssert(conversationStyle);
    OWSAssert(viewItem.unreadIndicator || viewItem.shouldShowDate);

    self.titleLabel.textColor = Theme.primaryColor;
    self.subtitleLabel.textColor = Theme.primaryColor;

    [self configureLabelsWithViewItem:viewItem];

    CGFloat strokeThickness = [self strokeThicknessWithViewItem:viewItem];
    self.strokeView.layer.cornerRadius = strokeThickness * 0.5f;
    self.strokeView.backgroundColor = [self strokeColorWithViewItem:viewItem];

    self.subtitleLabel.hidden = self.subtitleLabel.text.length < 1;

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.strokeView autoSetDimension:ALDimensionHeight toSize:strokeThickness],

        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:conversationStyle.headerGutterLeading],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:conversationStyle.headerGutterTrailing]
    ];
}

- (CGFloat)strokeThicknessWithViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    if (viewItem.unreadIndicator) {
        return 4.f;
    } else {
        return 1.f;
    }
}

- (UIColor *)strokeColorWithViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    if (viewItem.unreadIndicator) {
        return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.48f alpha:1.0f] : [UIColor colorWithWhite:0.40f alpha:1.0f]);
    } else {
        return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.70f alpha:1.0f] : [UIColor colorWithWhite:0.55f alpha:1.0f]);
    }
}

- (void)configureLabelsWithViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert(viewItem);

    NSDate *date = viewItem.interaction.dateForSorting;
    NSString *dateString = [DateUtil formatDateForConversationDateBreaks:date].localizedUppercaseString;

    // Update cell to reflect changes in dynamic text.
    if (viewItem.unreadIndicator) {
        self.titleLabel.font = UIFont.ows_dynamicTypeCaption1Font.ows_mediumWeight;

        NSString *title = NSLocalizedString(
            @"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.");
        if (viewItem.shouldShowDate) {
            title = [[dateString rtlSafeAppend:@" \u00B7 "] rtlSafeAppend:title];
        }
        self.titleLabel.text = title.localizedUppercaseString;

        if (!viewItem.unreadIndicator.hasMoreUnseenMessages) {
            self.subtitleLabel.text = nil;
        } else {
            self.subtitleLabel.text = (viewItem.unreadIndicator.missingUnseenSafetyNumberChangeCount > 0
                    ? NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES",
                          @"Messages that indicates that there are more unseen messages.")
                    : NSLocalizedString(
                          @"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_AND_SAFETY_NUMBER_CHANGES",
                          @"Messages that indicates that there are more unseen messages including safety number "
                          @"changes."));
        }
    } else {
        self.titleLabel.font = UIFont.ows_dynamicTypeCaption1Font;
        self.titleLabel.text = dateString;
        self.subtitleLabel.text = nil;
    }
}

- (CGSize)measureWithConversationViewItem:(ConversationViewItem *)viewItem
                        conversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssert(viewItem);
    OWSAssert(conversationStyle);
    OWSAssert(viewItem.unreadIndicator || viewItem.shouldShowDate);

    [self configureLabelsWithViewItem:viewItem];

    CGSize result = CGSizeMake(conversationStyle.viewWidth, 0);

    CGFloat strokeThickness = [self strokeThicknessWithViewItem:viewItem];
    result.height += strokeThickness;

    CGFloat maxTextWidth = conversationStyle.headerViewContentWidth;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
    result.height += titleSize.height + self.stackView.spacing;

    if (self.subtitleLabel.text.length > 0) {
        CGSize subtitleSize = [self.subtitleLabel sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
        result.height += subtitleSize.height + self.stackView.spacing;
    }
    result.height += OWSMessageHeaderViewDateHeaderVMargin;

    return CGSizeCeil(result);
}

@end

NS_ASSUME_NONNULL_END
