//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSystemMessageCell.h"
#import "Environment.h"
#import "NSBundle+JSQMessages.h"
#import "OWSContactsManager.h"
#import "TSUnreadIndicatorInteraction.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSystemMessageCell ()

@property (nonatomic, nullable) TSInteraction *interaction;

@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UILabel *titleLabel;

// override from JSQMessagesCollectionViewCell
@property (nonatomic) UILabel *cellTopLabel;

@end

#pragma mark -

@implementation OWSSystemMessageCell

// override from JSQMessagesCollectionViewCell
@synthesize cellTopLabel = _cellTopLabel;

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
    OWSAssert(!self.imageView);

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.backgroundColor = [UIColor whiteColor];

    self.cellTopLabel = [UILabel new];
    self.cellTopLabel.textAlignment = NSTextAlignmentCenter;
    self.cellTopLabel.font = self.topLabelFont;
    self.cellTopLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.cellTopLabel];

    self.imageView = [UIImageView new];
    [self.contentView addSubview:self.imageView];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
    self.titleLabel.font = [self titleFont];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.contentView addSubview:self.titleLabel];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self addGestureRecognizer:longPress];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)configureWithInteraction:(TSInteraction *)interaction;
{
    OWSAssert(interaction);

    _interaction = interaction;

    UIImage *icon = [self iconForInteraction:self.interaction];
    self.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.imageView.tintColor = [self iconColorForInteraction:self.interaction];
    self.titleLabel.textColor = [self textColor];
    [self applyTitleForInteraction:self.interaction label:self.titleLabel];

    [self setNeedsLayout];
}

- (UIFont *)topLabelFont
{
    return [UIFont boldSystemFontOfSize:12.0f];
}

- (UIColor *)textColor
{
    return [UIColor colorWithRGBHex:0x303030];
}

- (UIColor *)iconColorForInteraction:(TSInteraction *)interaction
{
    // "Phone", "Shield" and "Hourglass" icons have a lot of "ink" so they
    // are less dark for balance.
    return [UIColor colorWithRGBHex:0x404040];
}

- (UIImage *)iconForInteraction:(TSInteraction *)interaction
{
    UIImage *result = nil;

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        switch (((TSErrorMessage *)self.interaction).errorType) {
            case TSErrorMessageNonBlockingIdentityChange:
            case TSErrorMessageWrongTrustedIdentityKey:
                result = [UIImage imageNamed:@"system_message_security"];
                break;
            case TSErrorMessageInvalidKeyException:
            case TSErrorMessageMissingKeyId:
            case TSErrorMessageNoSession:
            case TSErrorMessageInvalidMessage:
            case TSErrorMessageDuplicateMessage:
            case TSErrorMessageInvalidVersion:
            case TSErrorMessageUnknownContactBlockOffer:
            case TSErrorMessageGroupCreationFailed:
                result = [UIImage imageNamed:@"system_message_info"];
                break;
        }
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        switch (((TSInfoMessage *)self.interaction).messageType) {
            case TSInfoMessageUserNotRegistered:
            case TSInfoMessageTypeSessionDidEnd:
            case TSInfoMessageTypeUnsupportedMessage:
            case TSInfoMessageAddToContactsOffer:
            case TSInfoMessageAddUserToProfileWhitelistOffer:
            case TSInfoMessageAddGroupToProfileWhitelistOffer:
                result = [UIImage imageNamed:@"system_message_info"];
                break;
            case TSInfoMessageTypeGroupUpdate:
            case TSInfoMessageTypeGroupQuit:
                result = [UIImage imageNamed:@"system_message_group"];
                break;
            case TSInfoMessageTypeDisappearingMessagesUpdate:
                result = [UIImage imageNamed:@"system_message_timer"];
                break;
            case TSInfoMessageVerificationStateChange:
                result = [UIImage imageNamed:@"system_message_verified"];

                OWSAssert([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]);
                if ([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
                    OWSVerificationStateChangeMessage *message = (OWSVerificationStateChangeMessage *)interaction;
                    BOOL isVerified = message.verificationState == OWSVerificationStateVerified;
                    if (!isVerified) {
                        result = [UIImage imageNamed:@"system_message_info"];
                    }
                }
                break;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        result = [UIImage imageNamed:@"system_message_call"];
    } else {
        OWSFail(@"Unknown interaction type: %@", [interaction class]);
        return nil;
    }
    OWSAssert(result);
    return result;
}

- (void)applyTitleForInteraction:(TSInteraction *)interaction label:(UILabel *)label
{
    OWSAssert(interaction);
    OWSAssert(label);

    // TODO: Should we move the copy generation into this view?

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        label.text = interaction.description;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        if ([interaction isKindOfClass:[OWSVerificationStateChangeMessage class]]) {
            OWSVerificationStateChangeMessage *message = (OWSVerificationStateChangeMessage *)interaction;
            BOOL isVerified = message.verificationState == OWSVerificationStateVerified;
            NSString *displayName =
                [[Environment getCurrent].contactsManager displayNameForPhoneIdentifier:message.recipientId];
            NSString *titleFormat = (isVerified
                    ? (message.isLocalChange
                              ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                                    @"Format for info message indicating that the verification state was verified on "
                                    @"this device. Embeds {{user's name or phone number}}.")
                              : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                                    @"Format for info message indicating that the verification state was verified on "
                                    @"another device. Embeds {{user's name or phone number}}."))
                    : (message.isLocalChange
                              ? NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                                    @"Format for info message indicating that the verification state was unverified on "
                                    @"this device. Embeds {{user's name or phone number}}.")
                              : NSLocalizedString(@"VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                                    @"Format for info message indicating that the verification state was unverified on "
                                    @"another device. Embeds {{user's name or phone number}}.")));
            label.text = [NSString stringWithFormat:titleFormat, displayName];
        } else {
            label.text = interaction.description;
        }
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        label.text = interaction.description;
    } else {
        OWSFail(@"Unknown interaction type: %@", [interaction class]);
        label.text = nil;
    }
}

- (UIFont *)titleFont
{
    return [UIFont ows_regularFontWithSize:13.f];
}

- (CGFloat)hMargin
{
    return 25.f;
}

- (CGFloat)topVMargin
{
    return 5.f;
}

- (CGFloat)bottomVMargin
{
    return 5.f;
}

- (CGFloat)hSpacing
{
    return 8.f;
}

- (CGFloat)iconSize
{
    return 20.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat maxTitleWidth = (self.contentView.width - ([self hMargin] * 2.f + [self hSpacing] + [self iconSize]));
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];

    CGFloat contentWidth = ([self iconSize] + [self hSpacing] + titleSize.width);

    CGSize topLabelSize = [self.cellTopLabel sizeThatFits:CGSizeMake(self.contentView.width, CGFLOAT_MAX)];
    self.cellTopLabel.frame = CGRectMake(0, 0, self.contentView.frame.size.width, topLabelSize.height);

    CGFloat topLabelSpacing = topLabelSize.height;

    self.imageView.frame = CGRectMake(round((self.contentView.width - contentWidth) * 0.5f),
        round((self.contentView.height - [self iconSize] + topLabelSpacing) * 0.5f),
        [self iconSize],
        [self iconSize]);

    self.titleLabel.frame = CGRectMake(round(self.imageView.right + [self hSpacing]),
        round((self.contentView.height - titleSize.height + topLabelSpacing) * 0.5f),
        ceil(titleSize.width + 1.f),
        ceil(titleSize.height + 1.f));
}

- (CGSize)bubbleSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    [self applyTitleForInteraction:interaction label:self.titleLabel];
    CGFloat maxTitleWidth = (collectionViewWidth - ([self hMargin] * 2.f + [self hSpacing] + [self iconSize]));
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(maxTitleWidth, CGFLOAT_MAX)];

    CGFloat contentHeight = ceil(MAX([self iconSize], titleSize.height));
    result.height += contentHeight;

    return result;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.interaction = nil;
}

#pragma mark - editing

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)delete:(nullable id)sender
{
    DDLogInfo(@"%@ chose delete", self.logTag);
    OWSAssert(self.interaction);

    [self.interaction remove];
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)tap
{
    OWSAssert(self.interaction);

    [self.systemMessageCellDelegate didTapSystemMessageWithInteraction:self.interaction];
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
    OWSAssert(self.interaction);
    if (longPress.state == UIGestureRecognizerStateBegan) {
        [self.systemMessageCellDelegate didLongPressSystemMessageCell:self];
    }
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
