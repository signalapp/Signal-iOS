//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+OWS.h"
#import "Theme.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>

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
