//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSDevice.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceTableViewCell : UITableViewCell

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *linkedLabel;
@property (nonatomic) UILabel *lastSeenLabel;

- (void)configureWithDevice:(OWSDevice *)device unlinkAction:(void (^)(void))unlinkAction;

@end

NS_ASSUME_NONNULL_END
