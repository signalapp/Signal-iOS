//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSDevice.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceTableViewCell : UITableViewCell

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *linkedLabel;
@property (nonatomic) UILabel *lastSeenLabel;

- (void)configureWithDevice:(OWSDevice *)device;

@end

NS_ASSUME_NONNULL_END
