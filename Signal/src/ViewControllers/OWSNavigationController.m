//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"

@interface OWSNavigationController ()

@end

#pragma mark -

@implementation OWSNavigationController

- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item
{

    UIViewController *topViewController = self.topViewController;
    BOOL wasBackButtonClicked = topViewController.navigationItem == item;

    if (wasBackButtonClicked) {
        if ([topViewController respondsToSelector:@selector(navBackButtonPressed)]) {
            // if user did press back on the view controller where you handle the navBackButtonPressed
            [topViewController performSelector:@selector(navBackButtonPressed)];
            return NO;
        } else {
            // if user did press back but you are not on the view controller that can handle the navBackButtonPressed
            [self popViewControllerAnimated:YES];
            return YES;
        }
    } else {
        // when you call popViewController programmatically you do not want to pop it twice
        return YES;
    }
}

@end
