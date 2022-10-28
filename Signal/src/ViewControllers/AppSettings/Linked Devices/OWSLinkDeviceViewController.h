//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/OWSViewControllerObjc.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSDeviceProvisioningURLParser;

@protocol OWSLinkDeviceViewControllerDelegate

- (void)expectMoreDevices;

@end

#pragma mark -

@interface OWSLinkDeviceViewController : OWSViewControllerObjc

@property (nonatomic, weak) id<OWSLinkDeviceViewControllerDelegate> delegate;

- (void)provisionWithConfirmationWithParser:(OWSDeviceProvisioningURLParser *)parser;

@end

NS_ASSUME_NONNULL_END
