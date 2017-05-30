//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSUnreadIndicatorCell.h"
#import "NSBundle+JSQMessages.h"
#import "OWSBezierPathView.h"
#import "TSUnreadIndicatorInteraction.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>

@interface OWSUnreadIndicatorCell ()

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) OWSBezierPathView *leftPathView;
@property (nonatomic) OWSBezierPathView *rightPathView;

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
        self.titleLabel = [UILabel new];
        self.titleLabel.text = [OWSUnreadIndicatorCell titleForInteraction:self.interaction];
        self.titleLabel.textColor = [UIColor ows_infoMessageBorderColor];
        self.titleLabel.font = [OWSUnreadIndicatorCell textFont];
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.text = [OWSUnreadIndicatorCell subtitleForInteraction:self.interaction];
        self.subtitleLabel.textColor = [UIColor ows_infoMessageBorderColor];
        self.subtitleLabel.font = [OWSUnreadIndicatorCell textFont];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.subtitleLabel];

        CGFloat kLineThickness = 0.5f;
        CGFloat kLineMargin = 5.f;
        ConfigureShapeLayerBlock configureShapeLayerBlock = ^(CAShapeLayer *layer, CGRect bounds) {
            OWSCAssert(layer);

            CGRect pathBounds
                = CGRectMake(0, (bounds.size.height - kLineThickness) * 0.5f, bounds.size.width, kLineThickness);
            pathBounds = CGRectInset(pathBounds, kLineMargin, 0);
            UIBezierPath *path = [UIBezierPath bezierPathWithRect:pathBounds];
            layer.path = path.CGPath;
            layer.fillColor = [[UIColor ows_infoMessageBorderColor] colorWithAlphaComponent:0.5f].CGColor;
        };

        self.leftPathView = [OWSBezierPathView new];
        self.leftPathView.configureShapeLayerBlock = configureShapeLayerBlock;
        [self.contentView addSubview:self.leftPathView];

        self.rightPathView = [OWSBezierPathView new];
        self.rightPathView.configureShapeLayerBlock = configureShapeLayerBlock;
        [self.contentView addSubview:self.rightPathView];
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

+ (CGFloat)vMargin
{
    return 5.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    [self.titleLabel sizeToFit];
    if (self.subtitleLabel.text.length < 1) {
        [self.titleLabel centerOnSuperview];
    } else {
        CGSize subtitleSize = [self.subtitleLabel
            sizeThatFits:CGSizeMake(
                             self.contentView.width - [OWSUnreadIndicatorCell subtitleHMargin] * 2.f, CGFLOAT_MAX)];
        CGFloat contentHeight
            = ceil(self.titleLabel.height) + OWSUnreadIndicatorCell.subtitleVSpacing + ceil(subtitleSize.height);

        self.titleLabel.frame = CGRectMake(round((self.titleLabel.superview.width - self.titleLabel.width) * 0.5f),
            round((self.titleLabel.superview.height - contentHeight) * 0.5f),
            ceil(self.titleLabel.width),
            ceil(self.titleLabel.height));
        self.subtitleLabel.frame = CGRectMake(round((self.titleLabel.superview.width - subtitleSize.width) * 0.5f),
            round(self.titleLabel.bottom + OWSUnreadIndicatorCell.subtitleVSpacing),
            ceil(subtitleSize.width),
            ceil(subtitleSize.height));
    }

    self.leftPathView.frame = CGRectMake(0, self.titleLabel.top, self.titleLabel.left, self.titleLabel.height);
    self.rightPathView.frame = CGRectMake(
        self.titleLabel.right, self.titleLabel.top, self.width - self.titleLabel.right, self.titleLabel.height);
}

+ (CGSize)cellSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
             collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    result.height += self.vMargin * 2.f;

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
