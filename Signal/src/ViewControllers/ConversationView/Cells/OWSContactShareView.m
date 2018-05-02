//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShareView.h"
#import "OWSContactAvatarBuilder.h"
#import "Signal-Swift.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSContact.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactShareView ()

@property (nonatomic) OWSContact *contactShare;
@property (nonatomic) BOOL isIncoming;

@end

#pragma mark -

@implementation OWSContactShareView

- (instancetype)initWithContactShare:(OWSContact *)contactShare isIncoming:(BOOL)isIncoming
{
    self = [super init];

    if (self) {
        _contactShare = contactShare;
        _isIncoming = isIncoming;
    }

    return self;
}

#pragma mark -

- (CGFloat)iconHMargin
{
    return 12.f;
}

- (CGFloat)iconHSpacing
{
    return 10.f;
}

+ (CGFloat)iconVMargin
{
    return 12.f;
}

- (CGFloat)iconVMargin
{
    return [OWSContactShareView iconVMargin];
}

+ (CGFloat)bubbleHeight
{
    return self.iconSize + self.iconVMargin * 2;
}

- (CGFloat)bubbleHeight
{
    return [OWSContactShareView bubbleHeight];
}

+ (CGFloat)iconSize
{
    return 44.f;
}

- (CGFloat)iconSize
{
    return [OWSContactShareView iconSize];
}

- (CGFloat)vMargin
{
    return 10.f;
}

- (UIColor *)bubbleBackgroundColor
{
    return self.isIncoming ? [UIColor jsq_messageBubbleLightGrayColor] : [UIColor ows_materialBlueColor];
}

- (void)createContents
{
    self.backgroundColor = [UIColor colorWithRGBHex:0xefeff4];
    self.layoutMargins = UIEdgeInsetsZero;

    // TODO: Verify that this layout works in RTL.
    const CGFloat kBubbleTailWidth = 6.f;

    UIView *contentView = [UIView containerView];
    [self addSubview:contentView];
    [contentView autoPinLeadingToSuperviewMarginWithInset:self.isIncoming ? kBubbleTailWidth : 0.f];
    [contentView autoPinTrailingToSuperviewMarginWithInset:self.isIncoming ? 0.f : kBubbleTailWidth];
    [contentView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.vMargin];
    [contentView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.vMargin];

    AvatarImageView *avatarView = [AvatarImageView new];
    // TODO: What's the best colorSeed value to use?
    OWSAvatarBuilder *avatarBuilder =
        [[OWSContactAvatarBuilder alloc] initWithNonSignalName:self.contactShare.displayName
                                                     colorSeed:self.contactShare.displayName
                                                      diameter:(NSUInteger)self.iconSize
                                               contactsManager:[Environment current].contactsManager];
    avatarView.image = [avatarBuilder build];
    [avatarView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [avatarView setCompressionResistanceHigh];
    [avatarView setContentHuggingHigh];

    UILabel *topLabel = [UILabel new];
    topLabel.text = self.contactShare.displayName;
    topLabel.textColor = [UIColor blackColor];
    topLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    topLabel.font = [UIFont ows_dynamicTypeBodyFont];

    UIStackView *labelsView = [UIStackView new];
    labelsView.axis = UILayoutConstraintAxisVertical;
    labelsView.spacing = 2;
    [labelsView addArrangedSubview:topLabel];

    // TODO: Should we just try to show the _first_ phone number?
    // What about email?
    // What if the second phone number is a signal account?
    NSString *_Nullable firstPhoneNumber = self.contactShare.phoneNumbers.firstObject.phoneNumber;
    if (firstPhoneNumber.length > 0) {
        UILabel *bottomLabel = [UILabel new];
        bottomLabel.text = firstPhoneNumber;
        // TODO:
        bottomLabel.textColor = [UIColor ows_darkGrayColor];
        bottomLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        bottomLabel.font = [UIFont ows_dynamicTypeCaption1Font];
        [labelsView addArrangedSubview:bottomLabel];
    }

    UIImage *disclosureImage =
        [UIImage imageNamed:(self.isRTL ? @"system_disclosure_indicator_rtl" : @"system_disclosure_indicator")];
    OWSAssert(disclosureImage);
    UIImageView *disclosureImageView = [UIImageView new];
    disclosureImageView.image = [disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    disclosureImageView.tintColor = [UIColor blackColor];
    [disclosureImageView setCompressionResistanceHigh];
    [disclosureImageView setContentHuggingHigh];

    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.spacing = self.iconHSpacing;
    stackView.alignment = UIStackViewAlignmentCenter;
    [contentView addSubview:stackView];
    [stackView autoPinLeadingToSuperviewMarginWithInset:self.iconHMargin];
    [stackView autoPinTrailingToSuperviewMarginWithInset:self.iconHMargin];
    [stackView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    // We pin pin to the superview _edge_ and not _margin_ for the purposes
    // of overflow, so that changes to the margins do not trip these safe guards.
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];

    [stackView addArrangedSubview:avatarView];
    [stackView addArrangedSubview:labelsView];
    [stackView addArrangedSubview:disclosureImageView];
}

@end

NS_ASSUME_NONNULL_END
