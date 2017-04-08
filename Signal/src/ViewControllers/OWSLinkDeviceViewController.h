//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSQRCodeScanningViewController.h"

@class OWSLinkedDevicesTableViewController;

@interface OWSLinkDeviceViewController : UIViewController <OWSQRScannerDelegate>

@property OWSLinkedDevicesTableViewController *linkedDevicesTableViewController;

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string;

@end
