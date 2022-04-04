//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "UIColor+OWS.h"
#import <SessionUtilitiesKit/AppContext.h>

#import <SessionUIKit/SessionUIKit.h>

#define CONTACT_PICTURE_VIEW_BORDER_WIDTH 0.5f

@implementation UIUtil

+ (void)applyRoundedBorderToImageView:(UIImageView *)imageView
{
    imageView.layer.borderWidth = CONTACT_PICTURE_VIEW_BORDER_WIDTH;
    imageView.layer.borderColor = [UIColor clearColor].CGColor;
    imageView.layer.cornerRadius = CGRectGetWidth(imageView.frame) / 2;
    imageView.layer.masksToBounds = YES;
}

+ (void)removeRoundedBorderToImageView:(UIImageView *__strong *)imageView
{
    [[*imageView layer] setBorderWidth:0];
    [[*imageView layer] setCornerRadius:0];
}

+ (void)setupSignalAppearence
{
    UINavigationBar.appearance.barTintColor = UIColor.whiteColor;
    UINavigationBar.appearance.translucent = NO;
    UINavigationBar.appearance.tintColor = UIColor.blackColor;
    UIToolbar.appearance.barTintColor = UIColor.blackColor;
    UIToolbar.appearance.translucent = NO;
    UIToolbar.appearance.tintColor = UIColor.whiteColor;
    
    UIBarButtonItem.appearance.tintColor = UIColor.blackColor;
    [UISwitch.appearance setOnTintColor:LKColors.accent];
    [UIToolbar.appearance setTintColor:LKColors.accent];
    
    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : UIColor.blackColor };
}

@end
