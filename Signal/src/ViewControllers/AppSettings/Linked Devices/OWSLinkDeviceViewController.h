//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/OWSViewControllerObjc.h>

NS_ASSUME_NONNULL_BEGIN

@class DeviceProvisioningURL;

@protocol OWSLinkDeviceViewControllerDelegate

- (void)expectMoreDevices;

@end

#pragma mark -

@interface OWSLinkDeviceViewController : OWSViewControllerObjc

@property (nonatomic, weak) id<OWSLinkDeviceViewControllerDelegate> delegate;

- (void)confirmProvisioningWithUrl:(DeviceProvisioningURL *)deviceProvisioningURL;

// Exposed for Swift
- (void)popToLinkedDeviceList;

@end

NS_ASSUME_NONNULL_END
