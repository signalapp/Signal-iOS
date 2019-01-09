//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSLinkedDevicesTableViewController;

@interface OWSLinkDeviceViewController : OWSViewController

@property (nonatomic, weak) OWSLinkedDevicesTableViewController *linkedDevicesTableViewController;

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
