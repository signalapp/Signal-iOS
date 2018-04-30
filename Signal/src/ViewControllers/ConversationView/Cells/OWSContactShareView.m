//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShareView.h"
#import "UIColor+JSQMessages.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/OWSContactShare.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactShareView ()

@property (nonatomic) OWSContactShare *contactShare;
@property (nonatomic) NSString *contactShareName;
@property (nonatomic) BOOL isIncoming;

@end

#pragma mark -

@implementation OWSContactShareView

- (instancetype)initWithContactShare:(OWSContactShare *)contactShare
                    contactShareName:(NSString *)contactShareName
                          isIncoming:(BOOL)isIncoming
{
    self = [super init];

    if (self) {
        _contactShare = contactShare;
        _contactShareName = contactShareName;
        _isIncoming = isIncoming;
    }

    return self;
}

#pragma mark - JSQMessageMediaData protocol

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

    UIView *iconCircleView = [UIView containerView];
    iconCircleView.backgroundColor = [UIColor colorWithRGBHex:0x00ffff];
    iconCircleView.layer.cornerRadius = self.iconSize * 0.5f;
    [iconCircleView autoSetDimension:ALDimensionWidth toSize:self.iconSize];
    [iconCircleView autoSetDimension:ALDimensionHeight toSize:self.iconSize];
    [iconCircleView setCompressionResistanceHigh];
    [iconCircleView setContentHuggingHigh];

    // TODO: Use avatar, if present and downloaded. else default.
    UIImage *image = [UIImage imageNamed:@"attachment_file"];
    OWSAssert(image);
    UIImageView *imageView = [UIImageView new];
    imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageView.tintColor = self.bubbleBackgroundColor;
    [iconCircleView addSubview:imageView];
    [imageView autoCenterInSuperview];

    UILabel *topLabel = [UILabel new];
    topLabel.text = self.contactShareName;
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
    // NOTE: It's critical that we pin to the superview top and bottom _edge_ and not _margin_.
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];
    [stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:0 relation:NSLayoutRelationGreaterThanOrEqual];

    [stackView addArrangedSubview:iconCircleView];
    [stackView addArrangedSubview:labelsView];
    [stackView addArrangedSubview:disclosureImageView];
}

@end

NS_ASSUME_NONNULL_END
