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

@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UILabel *titleLabel;

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
        self.imageView = [UIImageView new];
        [self.contentView addSubview:self.imageView];

        self.titleLabel = [UILabel new];
        self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
        self.titleLabel.font = [OWSSystemMessageCell titleFont];
        self.titleLabel.numberOfLines = 0;
        self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:self.titleLabel];
    }

    UIImage *icon = [self iconForInteraction:self.interaction];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.imageView.tintColor = [self iconColorForInteraction:self.interaction];
    self.titleLabel.text = [OWSSystemMessageCell titleForInteraction:self.interaction];
    self.titleLabel.textColor = [self textColorForInteraction:self.interaction];

    [self setNeedsLayout];
}

- (UIColor *)textColorForInteraction:(TSInteraction *)interaction
{
    return [UIColor colorWithRGBHex:0x303030];
}

- (UIColor *)iconColorForInteraction:(TSInteraction *)interaction
{
    // "Phone", "Shield" and "Hourglass" icons have a lot of "ink" so they
    // are less dark for balance.
    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        switch (((TSErrorMessage *)self.interaction).errorType) {
            case TSErrorMessageInvalidKeyException:
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
            case TSErrorMessageMissingKeyId:
                return [UIColor colorWithRGBHex:0x404040];
                break;
            case TSErrorMessageNoSession:
            case TSErrorMessageInvalidMessage:
            case TSErrorMessageDuplicateMessage:
            case TSErrorMessageInvalidVersion:
            case TSErrorMessageUnknownContactBlockOffer:
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)self.interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
                break;
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
                break;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate:
                return [UIColor colorWithRGBHex:0x404040];
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        return [UIColor colorWithRGBHex:0x404040];
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }

    return [UIColor colorWithRGBHex:0x303030];
}

- (UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
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
                result = [UIImage imageNamed:@"system_message_info"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)self.interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
                result = [UIImage imageNamed:@"system_message_info"];
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
        result = [UIImage imageNamed:@"system_message_call"];
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }
    OWSAssert(result);
    return result;
}

+ (NSString *)titleForInteraction:(TSInteraction *)interaction
{
    // TODO: Should we move the copy generation into this view?

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        return interaction.description;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        return interaction.description;
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        return interaction.description;
    } else {
        OWSFail(@"Unknown interaction type");
        return nil;
    }
}

+ (UIFont *)titleFont
{
    return [UIFont ows_regularFontWithSize:13.f];
}

+ (CGFloat)hMargin
{
    return 25.f;
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
    return 7.f;
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

    CGFloat contentWidth = ([OWSSystemMessageCell iconSize] + [OWSSystemMessageCell hSpacing] + titleSize.width);
    self.imageView.frame = CGRectMake(round((self.contentView.width - contentWidth) * 0.5f),
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
