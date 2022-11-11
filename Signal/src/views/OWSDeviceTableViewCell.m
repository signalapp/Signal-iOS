//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDeviceTableViewCell.h"
#import <SignalMessaging/DateUtil.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalUI/OWSTableViewController.h>
#import <SignalUI/SignalUI-Swift.h>
#import <SignalUI/Theme.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceTableViewCell ()

@property (nonatomic) UIButton *unlinkButton;
@property (nonatomic, nullable) void (^unlinkAction)(void);

@end

@implementation OWSDeviceTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self configure];
    }
    return self;
}

- (void)configure
{
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    self.nameLabel = [UILabel new];
    self.linkedLabel = [UILabel new];
    self.lastSeenLabel = [UILabel new];
    self.unlinkButton = [UIButton new];
    self.unlinkButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.unlinkButton addTarget:self action:@selector(didTapUnlink) forControlEvents:UIControlEventTouchUpInside];
    [self.unlinkButton setImage:[[UIImage imageNamed:@"minus-circle-solid-24"]
                                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                       forState:UIControlStateNormal];
    self.unlinkButton.tintColor = UIColor.ows_accentRedColor;
    self.unlinkButton.hidden = YES;
    [self.unlinkButton autoSetDimension:ALDimensionWidth toSize:24];

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.linkedLabel,
        self.lastSeenLabel,
    ]];
    vStackView.axis = UILayoutConstraintAxisVertical;
    vStackView.alignment = UIStackViewAlignmentLeading;
    vStackView.spacing = 2;

    UIStackView *hStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.unlinkButton,
        vStackView,
    ]];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = 16;

    [self.contentView addSubview:hStackView];
    [hStackView autoPinEdgesToSuperviewMargins];
}

- (void)configureWithDevice:(OWSDevice *)device unlinkAction:(void (^)(void))unlinkAction
{
    OWSAssertDebug(device);

    self.nameLabel.font = OWSTableItem.primaryLabelFont;
    self.nameLabel.textColor = Theme.primaryTextColor;
    self.linkedLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
    self.linkedLabel.textColor = Theme.secondaryTextAndIconColor;
    self.lastSeenLabel.font = UIFont.ows_dynamicTypeFootnoteFont;
    self.lastSeenLabel.textColor = Theme.secondaryTextAndIconColor;

    // TODO: This is not super, but the best we can do until
    // OWSTableViewController2 supports delete actions for
    // the inset cell style (which probably means building
    // custom editing support)
    self.unlinkAction = unlinkAction;
    self.unlinkButton.hidden = !self.isEditing;

    if (SSKDebugFlags.internalSettings) {
        self.nameLabel.text
            = LocalizationNotNeeded([NSString stringWithFormat:@"#%ld: %@", device.deviceId, device.displayName]);
    } else {
        self.nameLabel.text = device.displayName;
    }

    NSString *linkedFormatString
        = NSLocalizedString(@"DEVICE_LINKED_AT_LABEL", @"{{Short Date}} when device was linked.");
    self.linkedLabel.text =
        [NSString stringWithFormat:linkedFormatString, [DateUtil.dateFormatter stringFromDate:device.createdAt]];

    NSString *lastSeenFormatString = NSLocalizedString(
        @"DEVICE_LAST_ACTIVE_AT_LABEL", @"{{Short Date}} when device last communicated with Signal Server.");

    NSDate *displayedLastSeenAt;
    // lastSeenAt is stored at day granularity. At midnight UTC.
    // Making it likely that when you first link a device it will
    // be "last seen" the day before it was created, which looks broken.
    if ([device.lastSeenAt compare:device.createdAt] == NSOrderedDescending) {
        displayedLastSeenAt = device.lastSeenAt;
    } else {
        displayedLastSeenAt = device.createdAt;
    }

    self.lastSeenLabel.text =
        [NSString stringWithFormat:lastSeenFormatString, [DateUtil.dateFormatter stringFromDate:displayedLastSeenAt]];
}

- (void)didTapUnlink
{
    self.unlinkAction();
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    [OWSTableItem configureCell:self];

    self.nameLabel.textColor = Theme.primaryTextColor;
    self.linkedLabel.textColor = Theme.secondaryTextAndIconColor;
    self.lastSeenLabel.textColor = Theme.secondaryTextAndIconColor;
}

@end

NS_ASSUME_NONNULL_END
