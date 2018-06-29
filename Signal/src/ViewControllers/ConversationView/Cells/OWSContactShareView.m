//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShareView.h"
#import "OWSContactAvatarBuilder.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalServiceKit/OWSContact.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactShareView ()

@property (nonatomic, readonly) ContactShareViewModel *contactShare;
@property (nonatomic, weak) id<OWSContactShareViewDelegate> delegate;

@property (nonatomic, readonly) BOOL isIncoming;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;

@property (nonatomic, nullable) UIView *buttonView;

@end

#pragma mark -

@implementation OWSContactShareView

- (instancetype)initWithContactShare:(ContactShareViewModel *)contactShare
                          isIncoming:(BOOL)isIncoming
                            delegate:(id<OWSContactShareViewDelegate>)delegate
{
    self = [super init];

    if (self) {
        _delegate = delegate;
        _contactShare = contactShare;
        _isIncoming = isIncoming;
        _contactsManager = [Environment current].contactsManager;
    }

    return self;
}

#pragma mark -

- (CGFloat)hMargin
{
    return 12.f;
}

- (CGFloat)iconHSpacing
{
    return 8.f;
}

+ (CGFloat)iconVMargin
{
    return 12.f;
}

- (CGFloat)iconVMargin
{
    return [OWSContactShareView iconVMargin];
}

+ (BOOL)hasSendTextButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);
    OWSAssert(contactsManager);

    return [contactShare systemContactsWithSignalAccountPhoneNumbers:contactsManager].count > 0;
}

+ (BOOL)hasInviteButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);
    OWSAssert(contactsManager);

    return [contactShare systemContactPhoneNumbers:contactsManager].count > 0;
}

+ (BOOL)hasAddToContactsButton:(ContactShareViewModel *)contactShare
{
    OWSAssert(contactShare);

    return [contactShare e164PhoneNumbers].count > 0;
}


+ (BOOL)hasAnyButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);

    return ([self hasSendTextButton:contactShare contactsManager:contactsManager] ||
        [self hasInviteButton:contactShare contactsManager:contactsManager] ||
        [self hasAddToContactsButton:contactShare]);
}

+ (CGFloat)bubbleHeightForContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssert(contactShare);

    OWSContactsManager *contactsManager = [Environment current].contactsManager;

    if ([self hasAnyButton:contactShare contactsManager:contactsManager]) {
        return self.contentHeight + self.buttonHeight;
    } else {
        return self.contentHeight;
    }
}

+ (CGFloat)contentHeight
{
    CGFloat labelsHeight = (self.nameFont.lineHeight + self.labelsVSpacing + self.subtitleFont.lineHeight);
    CGFloat contentHeight = MAX(self.iconSize, labelsHeight);
    contentHeight += self.iconVMargin * 2;
    return contentHeight;
}

+ (CGFloat)buttonHeight
{
    return MAX(44.f, self.buttonFont.lineHeight + self.buttonVMargin * 2);
}

+ (CGFloat)iconSize
{
    return 48.f;
}

- (CGFloat)iconSize
{
    return [OWSContactShareView iconSize];
}

- (CGFloat)vMargin
{
    return 10.f;
}

+ (UIFont *)nameFont
{
    return [UIFont ows_dynamicTypeBodyFont];
}

+ (UIFont *)subtitleFont
{
    return [UIFont ows_dynamicTypeCaption1Font];
}

+ (CGFloat)labelsVSpacing
{
    return 2;
}

+ (UIFont *)buttonFont
{
    return [UIFont ows_dynamicTypeBodyFont];
}

+ (CGFloat)buttonVMargin
{
    return 5;
}

- (void)createContents
{
    self.layoutMargins = UIEdgeInsetsZero;

    AvatarImageView *avatarView = [AvatarImageView new];
    avatarView.image =
        [self.contactShare getAvatarImageWithDiameter:self.iconSize contactsManager:self.contactsManager];

    [avatarView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [avatarView setCompressionResistanceHigh];
    [avatarView setContentHuggingHigh];

    UILabel *topLabel = [UILabel new];
    topLabel.text = self.contactShare.displayName;
    topLabel.textColor = [UIColor blackColor];
    topLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    topLabel.font = OWSContactShareView.nameFont;

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = OWSContactShareView.labelsVSpacing;
    [labelsView addArrangedSubview:topLabel];

    NSString *_Nullable firstPhoneNumber =
        [self.contactShare systemContactsWithSignalAccountPhoneNumbers:self.contactsManager].firstObject;
    if (firstPhoneNumber.length > 0) {
        UILabel *bottomLabel = [UILabel new];
        bottomLabel.text = [PhoneNumber bestEffortLocalizedPhoneNumberWithE164:firstPhoneNumber];
        bottomLabel.textColor = [UIColor ows_darkGrayColor];
        bottomLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        bottomLabel.font = OWSContactShareView.subtitleFont;
        [labelsView addArrangedSubview:bottomLabel];
    }

    UIImage *disclosureImage =
        [UIImage imageNamed:(CurrentAppContext().isRTL ? @"small_chevron_left" : @"small_chevron_right")];
    OWSAssert(disclosureImage);
    UIImageView *disclosureImageView = [UIImageView new];
    disclosureImageView.image = [disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    disclosureImageView.tintColor = [UIColor blackColor];
    [disclosureImageView setCompressionResistanceHigh];
    [disclosureImageView setContentHuggingHigh];

    UIStackView *hStackView = [UIStackView new];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = self.iconHSpacing;
    hStackView.alignment = UIStackViewAlignmentCenter;
    hStackView.layoutMarginsRelativeArrangement = YES;
    hStackView.layoutMargins = UIEdgeInsetsMake(self.vMargin, self.hMargin, self.vMargin, self.hMargin);
    [hStackView addArrangedSubview:avatarView];
    [hStackView addArrangedSubview:labelsView];
    [hStackView addArrangedSubview:disclosureImageView];

    UIStackView *vStackView = [UIStackView new];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.spacing = 0;
    [self addSubview:vStackView];
    [vStackView autoPinToSuperviewEdges];
    [vStackView addArrangedSubview:hStackView];

    if ([OWSContactShareView hasAnyButton:self.contactShare contactsManager:self.contactsManager]) {
        UILabel *label = [UILabel new];
        self.buttonView = label;
        if ([OWSContactShareView hasSendTextButton:self.contactShare contactsManager:self.contactsManager]) {
            label.text = NSLocalizedString(@"ACTION_SEND_MESSAGE", @"Label for 'sent message' button in contact view.");
        } else if ([OWSContactShareView hasInviteButton:self.contactShare contactsManager:self.contactsManager]) {
            label.text = NSLocalizedString(@"ACTION_INVITE", @"Label for 'invite' button in contact view.");
        } else if ([OWSContactShareView hasAddToContactsButton:self.contactShare]) {
            label.text = NSLocalizedString(@"CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.");
        } else {
            OWSFail(@"%@ unexpected button state.", self.logTag);
        }
        label.font = OWSContactShareView.buttonFont;
        label.textColor = UIColor.ows_materialBlueColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.backgroundColor = [UIColor whiteColor];
        [vStackView addArrangedSubview:label];
        [label autoSetDimension:ALDimensionHeight toSize:OWSContactShareView.buttonHeight];
    }
}

- (BOOL)handleTapGesture:(UITapGestureRecognizer *)sender
{
    if (!self.buttonView) {
        return NO;
    }
    CGPoint location = [sender locationInView:self.buttonView];
    if (!CGRectContainsPoint(self.buttonView.bounds, location)) {
        return NO;
    }

    if ([OWSContactShareView hasSendTextButton:self.contactShare contactsManager:self.contactsManager]) {
        [self.delegate didTapSendMessageToContactShare:self.contactShare];
    } else if ([OWSContactShareView hasInviteButton:self.contactShare contactsManager:self.contactsManager]) {
        [self.delegate didTapSendInviteToContactShare:self.contactShare];
    } else if ([OWSContactShareView hasAddToContactsButton:self.contactShare]) {
        [self.delegate didTapShowAddToContactUIForContactShare:self.contactShare];
    } else {
        OWSFail(@"%@ unexpected button tap.", self.logTag);
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
