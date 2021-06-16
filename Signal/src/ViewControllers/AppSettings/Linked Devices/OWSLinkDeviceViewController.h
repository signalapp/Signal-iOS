//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"
#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSDeviceProvisioningURLParser;

@protocol OWSLinkDeviceViewControllerDelegate

- (void)expectMoreDevices;

@end

#pragma mark -

@interface OWSLinkDeviceViewController : OWSViewController

@property (nonatomic, weak) id<OWSLinkDeviceViewControllerDelegate> delegate;

- (void)controller:(nullable OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string;

- (void)provisionWithConfirmationWithParser:(OWSDeviceProvisioningURLParser *)parser;

@end

NS_ASSUME_NONNULL_END
