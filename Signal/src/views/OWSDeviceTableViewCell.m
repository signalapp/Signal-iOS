//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDeviceTableViewCell.h"
#import "DateUtil.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDeviceTableViewCell

- (void)configureWithDevice:(OWSDevice *)device
{
    self.nameLabel.text = device.name;

    NSString *linkedFormatString = NSLocalizedString(@"Linked: %@", @"{Short Date} when device was linked.");
    self.linkedLabel.text =
        [NSString stringWithFormat:linkedFormatString, [DateUtil.dateFormatter stringFromDate:device.createdAt]];

    NSString *lastSeenFormatString
        = NSLocalizedString(@"Last seen: %@", @"{Short Date} when device last communicated with Signal Server.");
    self.lastSeenLabel.text =
        [NSString stringWithFormat:lastSeenFormatString, [DateUtil.dateFormatter stringFromDate:device.createdAt]];
}

@end

NS_ASSUME_NONNULL_END
