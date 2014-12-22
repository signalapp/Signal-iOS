//
//  UIDevice+TSHardwareVersion.h
//  Signal
//
//  Created by Dylan Bourgeois on 19/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
//  Original Source :
//  Erica Sadun, http://ericasadun.com
//  iPhone Developer's Cookbook, 6.x Edition
//  BSD License, Use at your own risk
//
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, UIDeviceFamily) {
    UIDeviceFamilyiPhone,
    UIDeviceFamilyiPod,
    UIDeviceFamilyiPad,
    UIDeviceFamilyAppleTV,
    UIDeviceFamilyUnknown,
};


@interface UIDevice (TSHardwareVersion)

/**
 Returns a machine-readable model name in the format of "iPhone4,1"
 */
- (NSString *)modelIdentifier;

/**
 Returns a human-readable model name in the format of "iPhone 4S". Fallback of the the `modelIdentifier` value.
 */
- (NSString *)modelName;

/**
 Returns the device family as a `UIDeviceFamily`
 */
- (UIDeviceFamily)deviceFamily;

/*
 * Returns true if device is iPhone 6 or 6+
 */
- (BOOL)isiPhoneVersionSixOrMore;

@end
