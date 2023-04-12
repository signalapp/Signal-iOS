//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Theme.h"
#import "UIView+SignalUI.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (OWS)

- (UIViewController *)findFrontmostViewController:(BOOL)ignoringAlerts
{
    NSMutableArray<UIViewController *> *visitedViewControllers = [NSMutableArray new];

    UIViewController *viewController = self;
    while (YES) {
        [visitedViewControllers addObject:viewController];

        UIViewController *_Nullable nextViewController = viewController.presentedViewController;
        if (nextViewController) {
            BOOL nextViewControllerIsAlert = [nextViewController isKindOfClass:[ActionSheetController class]] ||
                [nextViewController isKindOfClass:[UIAlertController class]];
            if (!ignoringAlerts || !nextViewControllerIsAlert) {
                if ([visitedViewControllers containsObject:nextViewController]) {
                    // Cycle detected.
                    return viewController;
                }
                viewController = nextViewController;
                continue;
            }
        }

        if ([viewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navigationController = (UINavigationController *)viewController;
            nextViewController = navigationController.topViewController;
            if (nextViewController) {
                if ([visitedViewControllers containsObject:nextViewController]) {
                    // Cycle detected.
                    return viewController;
                }
                viewController = nextViewController;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    return viewController;
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
