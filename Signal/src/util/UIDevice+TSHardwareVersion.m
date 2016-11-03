//
//  UIDevice+TSHardwareVersion.m
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

#include <sys/sysctl.h>
#import "UIDevice+TSHardwareVersion.h"

@implementation UIDevice (TSHardwareVersion)

// Look for phone-type devices with a width greater than or equal to the width
// of the original iPhone 6. Hopefully, this is somewhat future proof
- (BOOL)isiPhoneVersionSixOrMore {
    return
        self.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        ([[UIScreen mainScreen] scale] * [[UIScreen mainScreen] bounds].size.width) >= 750;
}

@end
