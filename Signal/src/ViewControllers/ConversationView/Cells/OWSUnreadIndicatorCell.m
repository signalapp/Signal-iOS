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
@property (nonatomic) UIStackView *stackView;

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
    self.strokeView.backgroundColor = [UIColor ows_darkSkyBlueColor];
    [self.strokeView autoSetDimension:ALDimensionHeight toSize:self.strokeThickness];
    self.strokeView.layer.cornerRadius = self.strokeThickness * 0.5f;
    [self.strokeView setContentHuggingHigh];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor ows_light90Color];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.textColor = [UIColor ows_light90Color];
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
    [self.contentView addSubview:self.stackView];

    [self configureFonts];
}

- (void)configureFonts
{
    // Update cell to reflect changes in dynamic text.
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

    self.subtitleLabel.hidden = self.subtitleLabel.text.length < 1;

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                         withInset:self.conversationStyle.fullWidthGutterLeading],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                         withInset:self.conversationStyle.fullWidthGutterTrailing],
    ];
}

- (NSString *)titleForInteraction:(TSUnreadIndicatorInteraction *)interaction
{
    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.")
        .localizedUppercaseString;
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

- (CGFloat)strokeThickness
{
    return 4.f;
}

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.conversationStyle);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    [self configureFonts];

    CGSize result = CGSizeMake(
        self.conversationStyle.fullWidthContentWidth, self.strokeThickness + self.titleLabel.font.lineHeight);

    TSUnreadIndicatorInteraction *interaction = (TSUnreadIndicatorInteraction *)self.viewItem.interaction;
    self.subtitleLabel.text = [self subtitleForInteraction:interaction];
    if (self.subtitleLabel.text.length > 0) {
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
