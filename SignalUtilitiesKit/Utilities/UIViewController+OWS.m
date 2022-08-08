//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUIKit/SessionUIKit.h>

#import <SessionUtilitiesKit/AppContext.h>

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
            if (!ignoringAlerts || ![nextViewController isKindOfClass:[UIAlertController class]]) {
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

- (UIBarButtonItem *)createOWSBackButton
{
    return [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];
}

- (UIBarButtonItem *)createOWSBackButtonWithTarget:(id)target selector:(SEL)selector
{
    return [[self class] createOWSBackButtonWithTarget:target selector:selector];
}

+ (UIBarButtonItem *)createOWSBackButtonWithTarget:(id)target selector:(SEL)selector
{
    OWSAssertDebug(target);
    OWSAssertDebug(selector);

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    BOOL isRTL = CurrentAppContext().isRTL;

    // Nudge closer to the left edge to match default back button item.
    const CGFloat kExtraLeftPadding = isRTL ? +0 : -8;

    // Give some extra hit area to the back button. This is a little smaller
    // than the default back button, but makes sense for our left aligned title
    // view in the MessagesViewController
    const CGFloat kExtraRightPadding = isRTL ? -0 : +10;

    // Extra hit area above/below
    const CGFloat kExtraHeightPadding = 8;

    // Matching the default backbutton placement is tricky.
    // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
    // so we adjust the imageEdgeInsets on a UIButton, then wrap that
    // in a UIBarButtonItem.
    [backButton addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];

    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *backImage = [[UIImage systemImageNamed:@"chevron.backward" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssertDebug(backImage);
    [backButton setImage:backImage forState:UIControlStateNormal];
    backButton.tintColor = LKColors.text;

    backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    backButton.imageEdgeInsets = UIEdgeInsetsMake(0, kExtraLeftPadding, 0, 0);

    CGRect buttonFrame = CGRectMake(0, 0, backImage.size.width + kExtraRightPadding, backImage.size.height + kExtraHeightPadding);
    backButton.frame = buttonFrame;

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:backButton accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"back")];
    backItem.width = buttonFrame.size.width;

    return backItem;
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
