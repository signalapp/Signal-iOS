//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicatorCell.h"
#import "ConversationViewItem.h"
#import <SignalMessaging/TSUnreadIndicatorInteraction.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnreadIndicatorCell ()

@property (nonatomic, nullable) TSUnreadIndicatorInteraction *interaction;

@property (nonatomic) UIView *bannerView;
@property (nonatomic) UIView *bannerTopHighlightView;
@property (nonatomic) UIView *bannerBottomHighlightView1;
@property (nonatomic) UIView *bannerBottomHighlightView2;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *subtitleLabel;

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
    OWSAssert(!self.bannerView);

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.backgroundColor = [UIColor whiteColor];

    self.bannerView = [UIView new];
    self.bannerView.backgroundColor = [UIColor colorWithRGBHex:0xf6eee3];
    [self.contentView addSubview:self.bannerView];

    self.bannerTopHighlightView = [UIView new];
    self.bannerTopHighlightView.backgroundColor = [UIColor colorWithRGBHex:0xf9f3eb];
    [self.bannerView addSubview:self.bannerTopHighlightView];

    self.bannerBottomHighlightView1 = [UIView new];
    self.bannerBottomHighlightView1.backgroundColor = [UIColor colorWithRGBHex:0xd1c6b8];
    [self.bannerView addSubview:self.bannerBottomHighlightView1];

    self.bannerBottomHighlightView2 = [UIView new];
    self.bannerBottomHighlightView2.backgroundColor = [UIColor colorWithRGBHex:0xdbcfc0];
    [self.bannerView addSubview:self.bannerBottomHighlightView2];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
    self.titleLabel.font = [self titleFont];
    [self.bannerView addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.textColor = [UIColor ows_infoMessageBorderColor];
    self.subtitleLabel.font = [self subtitleFont];
    // The subtitle may wrap to a second line.
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.subtitleLabel];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    TSUnreadIndicatorInteraction *interaction = (TSUnreadIndicatorInteraction *)self.viewItem.interaction;

    self.titleLabel.text = [self titleForInteraction:interaction];
    self.subtitleLabel.text = [self subtitleForInteraction:interaction];

    // Update cell to reflect changes in dynamic text.
    self.titleLabel.font = [self titleFont];
    self.subtitleLabel.font = [self subtitleFont];

    self.backgroundColor = [UIColor whiteColor];

    [self setNeedsLayout];
}

- (UIFont *)titleFont
{
    return UIFont.ows_dynamicTypeBodyFont;
}

- (UIFont *)subtitleFont
{
    return UIFont.ows_dynamicTypeCaption1Font;
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
    NSString *subtitleFormat = (interaction.missingUnseenSafetyNumberChangeCount > 0
            ? NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_FORMAT",
                  @"Messages that indicates that there are more unseen messages that be revealed by tapping the 'load "
                  @"earlier messages' button. Embeds {{the name of the 'load earlier messages' button}}")
            : NSLocalizedString(
                  @"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_AND_SAFETY_NUMBER_CHANGES_FORMAT",
                  @"Messages that indicates that there are more unseen messages including safety number changes that "
                  @"be revealed by tapping the 'load earlier messages' button. Embeds {{the name of the 'load earlier "
                  @"messages' button}}."));
    NSString *loadMoreButtonName = NSLocalizedString(
        @"load_earlier_messages", @"Label for button that loads more messages in conversation view.");
    return [NSString stringWithFormat:subtitleFormat, loadMoreButtonName];
}

- (CGFloat)subtitleHMargin
{
    return 20.f;
}

- (CGFloat)subtitleVSpacing
{
    return 3.f;
}

- (CGFloat)titleInnerHMargin
{
    return 10.f;
}

- (CGFloat)titleVMargin
{
    return 5.5f;
}

- (CGFloat)topVMargin
{
    return 5.f;
}

- (CGFloat)bottomVMargin
{
    return 5.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    [self.titleLabel sizeToFit];

    // It's a bit of a hack, but we use a view that extends _outside_ the cell's bounds
    // to draw its background, since we want the background to extend to the edges of the
    // collection view.
    //
    // This layout logic assumes that the cell insets are symmetrical and can be deduced
    // from the cell frame.
    CGRect bannerViewFrame = CGRectMake(-self.left,
        round(self.topVMargin),
        round(self.width + self.left * 2.f),
        round(self.titleLabel.height + self.titleVMargin * 2.f));
    self.bannerView.frame = [self convertRect:bannerViewFrame toView:self.contentView];

    // The highlights should be 1px (not 1pt), so adapt their thickness to
    // the device resolution.
    CGFloat kHighlightThickness = 1.f / [UIScreen mainScreen].scale;
    self.bannerTopHighlightView.frame = CGRectMake(0, 0, self.bannerView.width, kHighlightThickness);
    self.bannerBottomHighlightView1.frame
        = CGRectMake(0, self.bannerView.height - kHighlightThickness * 2.f, self.bannerView.width, kHighlightThickness);
    self.bannerBottomHighlightView2.frame
        = CGRectMake(0, self.bannerView.height - kHighlightThickness * 1.f, self.bannerView.width, kHighlightThickness);

    [self.titleLabel centerOnSuperview];

    if (self.subtitleLabel.text.length > 0) {
        CGSize subtitleSize = [self.subtitleLabel
            sizeThatFits:CGSizeMake(self.contentView.width - [self subtitleHMargin] * 2.f, CGFLOAT_MAX)];
        self.subtitleLabel.frame = CGRectMake(round((self.contentView.width - subtitleSize.width) * 0.5f),
            round(self.bannerView.bottom + self.subtitleVSpacing),
            ceil(subtitleSize.width),
            ceil(subtitleSize.height));
    }
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    TSUnreadIndicatorInteraction *interaction = (TSUnreadIndicatorInteraction *)self.viewItem.interaction;

    // Update cell to reflect changes in dynamic text.
    self.titleLabel.font = [self titleFont];
    self.subtitleLabel.font = [self subtitleFont];

    // TODO: Should we use viewWidth?
    CGSize result = CGSizeMake(viewWidth, 0);
    result.height += self.titleVMargin * 2.f;
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    NSString *title = [self titleForInteraction:interaction];
    NSString *subtitle = [self subtitleForInteraction:interaction];

    self.titleLabel.text = title;
    result.height += ceil([self.titleLabel sizeThatFits:CGSizeZero].height);

    if (subtitle.length > 0) {
        result.height += self.subtitleVSpacing;

        self.subtitleLabel.text = subtitle;
        result.height += ceil(
            [self.subtitleLabel sizeThatFits:CGSizeMake(viewWidth - self.subtitleHMargin * 2.f, CGFLOAT_MAX)].height);
    }

    return result;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.interaction = nil;
}

@end

NS_ASSUME_NONNULL_END
