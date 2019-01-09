//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDeviceTableViewCell.h"
#import "DateUtil.h"
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalMessaging/Theme.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

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

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.linkedLabel,
        self.lastSeenLabel,
    ]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentLeading;
    stackView.spacing = 2;
    [self.contentView addSubview:stackView];
    [stackView ows_autoPinToSuperviewMargins];
}

- (void)configureWithDevice:(OWSDevice *)device
{
    OWSAssertDebug(device);

    [OWSTableItem configureCell:self];

    self.nameLabel.font = UIFont.ows_dynamicTypeBodyFont;
    self.linkedLabel.font = UIFont.ows_dynamicTypeCaption1Font;
    self.lastSeenLabel.font = UIFont.ows_dynamicTypeCaption1Font;

    self.nameLabel.textColor = Theme.primaryColor;
    self.linkedLabel.textColor = Theme.secondaryColor;
    self.lastSeenLabel.textColor = Theme.secondaryColor;

    self.nameLabel.text = device.displayName;

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

@end

NS_ASSUME_NONNULL_END
