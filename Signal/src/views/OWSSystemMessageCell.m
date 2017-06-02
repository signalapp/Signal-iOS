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
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>

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

    UIColor *contentColor = [self colorForInteraction:self.interaction];
    UIImage *icon = [self iconForInteraction:self.interaction];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    //    self.imageView.tintColor = [UIColor colorWithRGBHex:0x505050];
    self.imageView.tintColor = contentColor;
    //    self.imageView.image = [OWSSystemMessageCell iconForInteraction:self.interaction];
    self.titleLabel.text = [OWSSystemMessageCell titleForInteraction:self.interaction];
    self.titleLabel.textColor = contentColor;

    //    DDLogError(@"----- %@ %@",
    //               [self.interaction class],
    //               self.interaction.description);

    [self setNeedsLayout];
    //    [self addRedBorder];
}

- (UIColor *)colorForInteraction:(TSInteraction *)interaction
{
    //    UIImage *result = nil;

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        switch (((TSErrorMessage *)self.interaction).errorType) {
            case TSErrorMessageInvalidKeyException:
                return [UIColor ows_yellowColor];
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
            case TSErrorMessageMissingKeyId:
                //                result = [UIImage imageNamed:@"system_message_security"];
                break;
            case TSErrorMessageNoSession:
            case TSErrorMessageInvalidMessage:
            case TSErrorMessageDuplicateMessage:
            case TSErrorMessageInvalidVersion:
            case TSErrorMessageUnknownContactBlockOffer:
                //                result = [UIImage imageNamed:@"system_message_warning"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)self.interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
                //                result = [UIImage imageNamed:@"system_message_warning"];
                break;
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
                //                result = [UIImage imageNamed:@"system_message_info"];
                break;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                // TODO:
                //                result = [UIImage imageNamed:@"system_message_info"];
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate:
                //                result = [UIImage imageNamed:@"system_message_timer"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        // TODO:
        //        result = [UIImage imageNamed:@"system_message_call"];
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }
    //    return [UIColor ows_darkGrayColor];
    return [UIColor colorWithRGBHex:0x505050];
}

- (UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        //        DDLogError(@"----- %@ %@: %d",
        //                   [self.interaction class],
        //                   self.interaction.description,
        //                   (int) ((TSErrorMessage *) self.interaction).errorType);
        switch (((TSErrorMessage *)self.interaction).errorType) {
            case TSErrorMessageInvalidKeyException:
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
            case TSErrorMessageMissingKeyId:
                result = [UIImage imageNamed:@"system_message_security"];
                break;
            case TSErrorMessageNoSession:
            case TSErrorMessageInvalidMessage:
            case TSErrorMessageDuplicateMessage:
            case TSErrorMessageInvalidVersion:
            case TSErrorMessageUnknownContactBlockOffer:
                result = [UIImage imageNamed:@"system_message_warning"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        //        DDLogError(@"----- %@ %@: %d",
        //                   [self.interaction class],
        //                   self.interaction.description,
        //                   (int) ((TSInfoMessage *) self.interaction).messageType);
        switch (((TSInfoMessage *)self.interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
                result = [UIImage imageNamed:@"system_message_warning"];
                break;
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
                result = [UIImage imageNamed:@"system_message_info"];
                break;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                result = [UIImage imageNamed:@"system_message_group"];
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate:
                result = [UIImage imageNamed:@"system_message_timer"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        // TODO:
        result = [UIImage imageNamed:@"system_message_call"];
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
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        // TODO: Should we move the copy generation into this view?
        return interaction.description;
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        //        switch (((TSCall *) self.interaction).callType) {
        //            case <#constant#>:
        //                <#statements#>
        //                break;
        //
        //            default:
        //                break;
        //        }
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
    return 8.f;
}

+ (CGFloat)iconSize
{
    return 25.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat maxTitleWidth = (self.contentView.width
        - ([OWSSystemMessageCell hMargin] * 2.f + [OWSSystemMessageCell hSpacing] + [OWSSystemMessageCell iconSize]));
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
    self.imageView.frame = CGRectMake(round([OWSSystemMessageCell hMargin]),
        round((self.contentView.height - [OWSSystemMessageCell iconSize]) * 0.5f),
        [OWSSystemMessageCell iconSize],
        [OWSSystemMessageCell iconSize]);
    self.titleLabel.frame = CGRectMake(round(self.imageView.right + [OWSSystemMessageCell hSpacing]),
        round((self.contentView.height - titleSize.height) * 0.5f),
        ceil(titleSize.width + 1.f),
        ceil(titleSize.height + 1.f));
}

+ (CGSize)cellSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    NSString *title = [self titleForInteraction:interaction];

    // Creating a UILabel to measure the layout is expensive, but it's the only
    // reliable way to do it.
    UILabel *label = [UILabel new];
    label.font = [self titleFont];
    label.text = title;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    CGFloat maxTitleWidth = (collectionViewWidth - ([self hMargin] * 2.f + [self hSpacing] + [self iconSize]));
    CGSize titleSize = [label sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];
    CGFloat contentHeight = ceil(MAX([self iconSize], titleSize.height));
    result.height += contentHeight;

    return result;
}

@end
