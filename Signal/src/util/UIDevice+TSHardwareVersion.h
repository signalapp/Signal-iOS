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


@interface UIDevice (TSHardwareVersion)

/*
 * Returns true if device is iPhone 6 or 6+
 */
- (BOOL)isiPhoneVersionSixOrMore;

@end
