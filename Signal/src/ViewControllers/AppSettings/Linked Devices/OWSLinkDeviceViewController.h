//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalUI/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSDeviceProvisioningURLParser;

@protocol OWSLinkDeviceViewControllerDelegate

- (void)expectMoreDevices;

@end

#pragma mark -

@interface OWSLinkDeviceViewController : OWSViewController

@property (nonatomic, weak) id<OWSLinkDeviceViewControllerDelegate> delegate;

- (void)provisionWithConfirmationWithParser:(OWSDeviceProvisioningURLParser *)parser;

@end

NS_ASSUME_NONNULL_END
