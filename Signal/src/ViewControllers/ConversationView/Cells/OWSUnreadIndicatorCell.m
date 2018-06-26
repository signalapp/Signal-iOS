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
@property (nonatomic) UILabel *subtitleLabel;
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
    self.strokeView.backgroundColor = [UIColor blackColor];
    [self.contentView addSubview:self.strokeView];

    self.titleLabel = [UILabel new];
    // TODO: color.
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    // TODO: color.
    self.subtitleLabel.textColor = [UIColor lightGrayColor];
    // The subtitle may wrap to a second line.
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.subtitleLabel];

    [self configureFonts];
}

- (void)configureFonts
{
    // Update cell to reflect changes in dynamic text.
    //
    // TODO: Font size.
    self.titleLabel.font = UIFont.ows_dynamicTypeCaption1Font.ows_mediumWeight;
    self.subtitleLabel.font = UIFont.ows_dynamicTypeCaption1Font;
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
    self.subtitleLabel.text = [self subtitleForInteraction:interaction];

    self.backgroundColor = [UIColor whiteColor];

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.titleLabel autoVCenterInSuperview],
        [self.titleLabel autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterLeading],
        [self.titleLabel autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterTrailing],

        [self.strokeView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.titleLabel],
        [self.strokeView autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterLeading],
        [self.strokeView autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterTrailing],
        [self.strokeView autoSetDimension:ALDimensionHeight toSize:1.f],

        [self.subtitleLabel autoPinEdge:ALEdgeTop
                                 toEdge:ALEdgeBottom
                                 ofView:self.titleLabel
                             withOffset:self.subtitleVSpacing],
        [self.subtitleLabel autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterLeading],
        [self.subtitleLabel autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.fullWidthGutterTrailing],
    ];
}

- (NSString *)titleForInteraction:(TSUnreadIndicatorInteraction *)interaction
{
    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.")
        .uppercaseString;
}

- (NSString *)subtitleForInteraction:(TSUnreadIndicatorInteraction *)interaction
{
    if (!interaction.hasMoreUnseenMessages) {
        return nil;
    }
    return (interaction.missingUnseenSafetyNumberChangeCount > 0
            ? NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES",
                  @"Messages that indicates that there are more unseen messages.")
            : NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_AND_SAFETY_NUMBER_CHANGES",
                  @"Messages that indicates that there are more unseen messages including safety number changes."));
}

- (CGFloat)subtitleVSpacing
{
    return 3.f;
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

    TSUnreadIndicatorInteraction *interaction = (TSUnreadIndicatorInteraction *)self.viewItem.interaction;
    self.subtitleLabel.text = [self subtitleForInteraction:interaction];
    if (self.subtitleLabel.text.length > 0) {
        result.height += self.subtitleVSpacing;
        result.height += ceil(
            [self.subtitleLabel sizeThatFits:CGSizeMake(self.conversationStyle.fullWidthContentWidth, CGFLOAT_MAX)]
                .height);
    }

    return CGSizeCeil(result);
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.interaction = nil;
}

@end

NS_ASSUME_NONNULL_END
