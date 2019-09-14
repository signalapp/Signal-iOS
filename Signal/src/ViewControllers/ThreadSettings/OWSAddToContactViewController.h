//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface OWSAddToContactViewController : OWSTableViewController

- (void)configureWithAddress:(SignalServiceAddress *)address;

@end

NS_ASSUME_NONNULL_END
