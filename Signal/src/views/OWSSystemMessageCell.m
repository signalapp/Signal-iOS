//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSystemMessageCell.h"
#import "NSBundle+JSQMessages.h"
#import "TSUnreadIndicatorInteraction.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>
#import <SignalServiceKit/TSErrorMessage.h>

@interface OWSSystemMessageCell ()

//@property (nonatomic) UIView *bannerView;
//@property (nonatomic) UIView *bannerTopHighlightView;
//@property (nonatomic) UIView *bannerBottomHighlightView1;
//@property (nonatomic) UIView *bannerBottomHighlightView2;
@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UILabel *titleLabel;
//@property (nonatomic) UILabel *subtitleLabel;

@end

#pragma mark -

@implementation OWSSystemMessageCell

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)configure
{
    self.backgroundColor = [UIColor whiteColor];

    if (!self.titleLabel) {
        //        self.bannerView = [UIView new];
        //        self.bannerView.backgroundColor = [UIColor colorWithRGBHex:0xf6eee3];
        //        [self.contentView addSubview:self.bannerView];
        //
        //        self.bannerTopHighlightView = [UIView new];
        //        self.bannerTopHighlightView.backgroundColor = [UIColor colorWithRGBHex:0xf9f3eb];
        //        [self.bannerView addSubview:self.bannerTopHighlightView];
        //
        //        self.bannerBottomHighlightView1 = [UIView new];
        //        self.bannerBottomHighlightView1.backgroundColor = [UIColor colorWithRGBHex:0xd1c6b8];
        //        [self.bannerView addSubview:self.bannerBottomHighlightView1];
        //
        //        self.bannerBottomHighlightView2 = [UIView new];
        //        self.bannerBottomHighlightView2.backgroundColor = [UIColor colorWithRGBHex:0xdbcfc0];
        //        [self.bannerView addSubview:self.bannerBottomHighlightView2];

        self.imageView = [UIImageView new];
        [self.contentView addSubview:self.imageView];

        self.titleLabel = [UILabel new];
        self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
        self.titleLabel.font = [OWSSystemMessageCell titleFont];
        self.titleLabel.numberOfLines = 0;
        self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:self.titleLabel];

        //        self.subtitleLabel = [UILabel new];
        //        self.subtitleLabel.text = [OWSSystemMessageCell subtitleForInteraction:self.interaction];
        //        self.subtitleLabel.textColor = [UIColor ows_infoMessageBorderColor];
        //        self.subtitleLabel.font = [OWSSystemMessageCell subtitleFont];
        //        self.subtitleLabel.numberOfLines = 0;
        //        self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        //        self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
        //        [self.contentView addSubview:self.subtitleLabel];
    }
    //    [self.imageView addRedBorder];
    //    [self addRedBorder];

    UIColor *contentColor = [UIColor ows_darkGrayColor];
    UIImage *icon = [self iconForInteraction:self.interaction];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    //    self.imageView.tintColor = [UIColor colorWithRGBHex:0x505050];
    self.imageView.tintColor = contentColor;
    //    self.imageView.image = [OWSSystemMessageCell iconForInteraction:self.interaction];
    self.titleLabel.text = [OWSSystemMessageCell titleForInteraction:self.interaction];
    self.titleLabel.textColor = contentColor;

    [self setNeedsLayout];
}

- (UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;
    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        // TODO:
        result = [UIImage imageNamed:@"system_message_security"];
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }
    OWSAssert(result);
    return result;
    //    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread
    //    messages.")
    //        .uppercaseString;
}

+ (NSString *)titleForInteraction:(TSInteraction *)interaction
{
    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        // TODO: Should we move the copy generation into this view?
        return interaction.description;
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }
    //    return NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR", @"Indicator that separates read from unread
    //    messages.")
    //        .uppercaseString;
}

+ (UIFont *)titleFont
{
    return [UIFont ows_regularFontWithSize:13.f];
}

//+ (UIFont *)subtitleFont
//{
//    return [UIFont ows_regularFontWithSize:12.f];
//}

//+ (NSString *)subtitleForInteraction:(TSUnreadIndicatorInteraction *)interaction
//{
//    if (!interaction.hasMoreUnseenMessages) {
//        return nil;
//    }
//    NSString *subtitleFormat = (interaction.missingUnseenSafetyNumberChangeCount > 0
//            ? NSLocalizedString(@"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_FORMAT",
//                  @"Messages that indicates that there are more unseen messages that be revealed by tapping the 'load
//                  "
//                  @"earlier messages' button. Embeds {{the name of the 'load earlier messages' button}}")
//            : NSLocalizedString(
//                  @"MESSAGES_VIEW_UNREAD_INDICATOR_HAS_MORE_UNSEEN_MESSAGES_AND_SAFETY_NUMBER_CHANGES_FORMAT",
//                  @"Messages that indicates that there are more unseen messages including safety number changes that "
//                  @"be revealed by tapping the 'load earlier messages' button. Embeds {{the name of the 'load earlier
//                  "
//                  @"messages' button}}."));
//    NSString *loadMoreButtonName = [NSBundle jsq_localizedStringForKey:@"load_earlier_messages"];
//    return [NSString stringWithFormat:subtitleFormat, loadMoreButtonName];
//}

//+ (CGFloat)subtitleHMargin
//{
//    return 20.f;
//}
//
//+ (CGFloat)subtitleVSpacing
//{
//    return 3.f;
//}
//
//+ (CGFloat)titleInnerHMargin
//{
//    return 10.f;
//}
//
//+ (CGFloat)titleVMargin
//{
//    return 5.5f;
//}

+ (CGFloat)hMargin
{
    return 30.f;
}

+ (CGFloat)topVMargin
{
    return 5.f;
}

+ (CGFloat)bottomVMargin
{
    return 5.f;
}

+ (CGFloat)hSpacing
{
    return 10.f;
}

+ (CGFloat)iconSize
{
    return 30.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    //    [self.titleLabel sizeToFit];
    //
    //    // It's a bit of a hack, but we use a view that extends _outside_ the cell's bounds
    //    // to draw its background, since we want the background to extend to the edges of the
    //    // collection view.
    //    //
    //    // This layout logic assumes that the cell insets are symmetrical and can be deduced
    //    // from the cell frame.
    //    CGRect bannerViewFrame = CGRectMake(-self.left,
    //        round(OWSSystemMessageCell.topVMargin),
    //        round(self.width + self.left * 2.f),
    //        round(self.titleLabel.height + OWSSystemMessageCell.titleVMargin * 2.f));
    //    self.bannerView.frame = [self convertRect:bannerViewFrame toView:self.contentView];
    //
    //    // The highlights should be 1px (not 1pt), so adapt their thickness to
    //    // the device resolution.
    //    CGFloat kHighlightThickness = 1.f / [UIScreen mainScreen].scale;
    //    self.bannerTopHighlightView.frame = CGRectMake(0, 0, self.bannerView.width, kHighlightThickness);
    //    self.bannerBottomHighlightView1.frame
    //        = CGRectMake(0, self.bannerView.height - kHighlightThickness * 2.f, self.bannerView.width,
    //        kHighlightThickness);
    //    self.bannerBottomHighlightView2.frame
    //        = CGRectMake(0, self.bannerView.height - kHighlightThickness * 1.f, self.bannerView.width,
    //        kHighlightThickness);
    //
    //    [self.titleLabel centerOnSuperview];

    CGFloat maxTitleWidth = (self.contentView.width
        - ([OWSSystemMessageCell hMargin] * 2.f + [OWSSystemMessageCell hSpacing] + [OWSSystemMessageCell iconSize]));
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
    //    CGFloat contentWidth = ceil([OWSSystemMessageCell iconSize] +
    //                                [OWSSystemMessageCell hSpacing] +
    //                                titleSize.width);
    //    self.imageView.frame = CGRectMake(round((self.contentView.width - contentWidth) * 0.5f),
    self.imageView.frame = CGRectMake(round([OWSSystemMessageCell hMargin]),
        round((self.contentView.height - [OWSSystemMessageCell iconSize]) * 0.5f),
        [OWSSystemMessageCell iconSize],
        [OWSSystemMessageCell iconSize]);
    self.titleLabel.frame = CGRectMake(round(self.imageView.right + [OWSSystemMessageCell hSpacing]),
        round((self.contentView.height - titleSize.height) * 0.5f),
        ceil(titleSize.width + 1.f),
        ceil(titleSize.height + 1.f));
    //    [self.titleLabel addRedBorder];
    //    if (self.subtitleLabel.text.length > 0) {
    //        CGSize subtitleSize = [self.subtitleLabel
    //            sizeThatFits:CGSizeMake(
    //                             self.contentView.width - [OWSSystemMessageCell subtitleHMargin] * 2.f, CGFLOAT_MAX)];
    //        self.subtitleLabel.frame = CGRectMake(round((self.contentView.width - subtitleSize.width) * 0.5f),
    //            round(self.bannerView.bottom + OWSSystemMessageCell.subtitleVSpacing),
    //            ceil(subtitleSize.width),
    //            ceil(subtitleSize.height));
    //    }
}

+ (CGSize)cellSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    //    result.height += self.titleVMargin * 2.f;
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    NSString *title = [self titleForInteraction:interaction];
    //    NSString *subtitle = [self subtitleForInteraction:interaction];

    // Creating a UILabel to measure the layout is expensive, but it's the only
    // reliable way to do it.  Unread indicators should be rare, so this is acceptable.
    UILabel *label = [UILabel new];
    label.font = [self titleFont];
    label.text = title;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    CGFloat maxTitleWidth = (collectionViewWidth - ([self hMargin] * 2.f + [self hSpacing] + [self iconSize]));
    CGSize titleSize = [label sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
    CGFloat contentHeight = ceil(MAX([self iconSize], titleSize.height));
    result.height += contentHeight;

    //    if (subtitle.length > 0) {
    //        result.height += self.subtitleVSpacing;
    //
    //        label.font = [self subtitleFont];
    //        label.text = subtitle;
    //        // The subtitle may wrap to a second line.
    //        label.lineBreakMode = NSLineBreakByWordWrapping;
    //        label.numberOfLines = 0;
    //        result.height += ceil(
    //            [label sizeThatFits:CGSizeMake(collectionViewWidth - self.subtitleHMargin * 2.f,
    //            CGFLOAT_MAX)].height);
    //    }

    return result;
}

@end
