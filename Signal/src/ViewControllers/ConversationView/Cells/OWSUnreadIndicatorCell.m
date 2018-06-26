//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicatorCell.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import <SignalMessaging/TSUnreadIndicatorInteraction.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnreadIndicatorCell ()

@property (nonatomic, nullable) TSUnreadIndicatorInteraction *interaction;

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIView *strokeView;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;

@end

#pragma mark -

@implementation OWSUnreadIndicatorCell

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
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    self.strokeView = [UIView new];
    // TODO: color.
    self.strokeView.backgroundColor = [UIColor colorWithRGBHex:0xf6eee3];
    [self.contentView addSubview:self.strokeView];

    self.titleLabel = [UILabel new];
    // TODO: color.
    self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLabel];

    [self configureFonts];
}

- (void)configureFonts
{
    // Update cell to reflect changes in dynamic text.
    //
    // TODO: Font size.
    self.titleLabel.font = UIFont.ows_dynamicTypeSubheadlineFont;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    [self configureFonts];

    TSUnreadIndicatorInteraction *interaction = (TSUnreadIndicatorInteraction *)self.viewItem.interaction;

    self.titleLabel.text = [self titleForInteraction:interaction];

    self.backgroundColor = [UIColor whiteColor];

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.titleLabel autoVCenterInSuperview],
        [self.titleLabel autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterLeading],
        [self.titleLabel autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterTrailing],

        // TODO: offset.
        [self.strokeView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.titleLabel withOffset:0.f],
        [self.strokeView autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterLeading],
        [self.strokeView autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterTrailing],
        [self.strokeView autoSetDimension:ALDimensionHeight toSize:1.f],
    ];
}

- (NSString *)titleForInteraction:(TSUnreadIndicatorInteraction *)interaction
{
    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.")
        .uppercaseString;
}

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    [self configureFonts];

    // TODO: offset.
    CGFloat vOffset = 24.f;
    CGSize result
        = CGSizeMake(self.conversationStyle.fullWidthContentWidth, self.titleLabel.font.lineHeight + vOffset * 2);

    return CGSizeCeil(result);
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.interaction = nil;
}

@end

NS_ASSUME_NONNULL_END
