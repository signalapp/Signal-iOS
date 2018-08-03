//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <SignalServiceKit/OWSDevice.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UILabel *linkedLabel;
@property (strong, nonatomic) IBOutlet UILabel *lastSeenLabel;

- (void)configureWithDevice:(OWSDevice *)device;

@end

NS_ASSUME_NONNULL_END
