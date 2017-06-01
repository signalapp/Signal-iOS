//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicatorCell.h"
#import "NSBundle+JSQMessages.h"
#import "TSUnreadIndicatorInteraction.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>

@interface OWSUnreadIndicatorCell ()

@property (nonatomic) UIView *titleBackgroundView;
@property (nonatomic) UIView *titleTopHighlightView;
@property (nonatomic) UIView *titleBottomHighlightView;
@property (nonatomic) UIView *titlePillView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *subtitleLabel;

@end

#pragma mark -

@implementation OWSUnreadIndicatorCell

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)configure
{
    self.backgroundColor = [UIColor whiteColor];

    if (!self.titleLabel) {
        self.titleBackgroundView = [UIView new];
        self.titleBackgroundView.backgroundColor = [UIColor colorWithRGBHex:0xe2e2e2];
        [self.contentView addSubview:self.titleBackgroundView];

        self.titleTopHighlightView = [UIView new];
        self.titleTopHighlightView.backgroundColor = [UIColor whiteColor];
        [self.titleBackgroundView addSubview:self.titleTopHighlightView];

        self.titleBottomHighlightView = [UIView new];
        self.titleBottomHighlightView.backgroundColor = [UIColor colorWithRGBHex:0xd1d1d1];
        [self.titleBackgroundView addSubview:self.titleBottomHighlightView];

        self.titlePillView = [UIView new];
        self.titlePillView.backgroundColor = [UIColor whiteColor];
        [self.titleBackgroundView addSubview:self.titlePillView];

        self.titleLabel = [UILabel new];
        self.titleLabel.text = [OWSUnreadIndicatorCell titleForInteraction:self.interaction];
        self.titleLabel.textColor = [UIColor blackColor];
        self.titleLabel.font = [OWSUnreadIndicatorCell textFont];
        [self.titlePillView addSubview:self.titleLabel];

        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.text = [OWSUnreadIndicatorCell subtitleForInteraction:self.interaction];
        self.subtitleLabel.textColor = [UIColor ows_infoMessageBorderColor];
        self.subtitleLabel.font = [OWSUnreadIndicatorCell textFont];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.subtitleLabel];
    }
}

+ (UIFont *)textFont
{
    return [UIFont ows_mediumFontWithSize:12.f];
}

+ (NSString *)titleForInteraction:(TSUnreadIndicatorInteraction *)interaction
{
    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread messages.");
}

+ (NSString *)subtitleForInteraction:(TSUnreadIndicatorInteraction *)interaction
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
    NSString *loadMoreButtonName = [NSBundle jsq_localizedStringForKey:@"load_earlier_messages"];
    return [NSString stringWithFormat:subtitleFormat, loadMoreButtonName];
}

+ (CGFloat)subtitleHMargin
{
    return 20.f;
}

+ (CGFloat)subtitleVSpacing
{
    return 3.f;
}

+ (CGFloat)titleInnerHMargin
{
    return 10.f;
}

+ (CGFloat)titleInnerVMargin
{
    return 5.f;
}

+ (CGFloat)titleOuterVMargin
{
    return 5.f;
}

+ (CGFloat)topVMargin
{
    return 5.f;
}

+ (CGFloat)bottomVMargin
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
    CGRect titleBackgroundViewFrame = CGRectMake(-self.left,
        OWSUnreadIndicatorCell.topVMargin,
        self.width + self.left * 2.f,
        self.titleLabel.height + OWSUnreadIndicatorCell.titleInnerVMargin * 2.f
            + OWSUnreadIndicatorCell.titleOuterVMargin * 2.f);
    self.titleBackgroundView.frame = [self convertRect:titleBackgroundViewFrame toView:self.contentView];

    self.titleTopHighlightView.frame = CGRectMake(0, 0, self.titleBackgroundView.width, 1.f);
    self.titleBottomHighlightView.frame
        = CGRectMake(0, self.titleBackgroundView.height - 1.f, self.titleBackgroundView.width, 1.f);

    self.titlePillView.frame = CGRectMake(0,
        0,
        self.titleLabel.width + OWSUnreadIndicatorCell.titleInnerHMargin * 2.f,
        self.titleLabel.height + OWSUnreadIndicatorCell.titleInnerVMargin * 2.f);
    self.titlePillView.layer.cornerRadius = self.titlePillView.height * 0.5f;
    [self.titlePillView centerOnSuperview];

    [self.titleLabel centerOnSuperview];

    if (self.subtitleLabel.text.length > 0) {
        CGSize subtitleSize = [self.subtitleLabel
            sizeThatFits:CGSizeMake(
                             self.contentView.width - [OWSUnreadIndicatorCell subtitleHMargin] * 2.f, CGFLOAT_MAX)];
        self.subtitleLabel.frame = CGRectMake(round((self.contentView.width - subtitleSize.width) * 0.5f),
            round(self.titleBackgroundView.bottom + OWSUnreadIndicatorCell.subtitleVSpacing),
            ceil(subtitleSize.width),
            ceil(subtitleSize.height));
    }
}

+ (CGSize)cellSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
             collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    result.height += self.titleInnerVMargin * 2.f;
    result.height += self.titleOuterVMargin * 2.f;
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    NSString *title = [self titleForInteraction:interaction];
    NSString *subtitle = [self subtitleForInteraction:interaction];

    // Creating a UILabel to measure the layout is expensive, but it's the only
    // reliable way to do it.  Unread indicators should be rare, so this is acceptable.
    UILabel *label = [UILabel new];
    label.font = [self textFont];
    label.text = title;
    result.height += ceil([label sizeThatFits:CGSizeZero].height);

    if (subtitle.length > 0) {
        result.height += self.subtitleVSpacing;

        label.text = subtitle;
        // The subtitle may wrap to a second line.
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        result.height += ceil(
            [label sizeThatFits:CGSizeMake(collectionViewWidth - self.subtitleHMargin * 2.f, CGFLOAT_MAX)].height);
    }

    return result;
}

@end
