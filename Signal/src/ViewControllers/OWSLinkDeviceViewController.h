//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"
#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSLinkedDevicesTableViewController;

@interface OWSLinkDeviceViewController : OWSViewController <OWSQRScannerDelegate>

@property OWSLinkedDevicesTableViewController *linkedDevicesTableViewController;

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
