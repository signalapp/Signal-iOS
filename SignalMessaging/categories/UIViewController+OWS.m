//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIColor+OWS.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/iOSVersions.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (OWS)

- (UIViewController *)findFrontmostViewController:(BOOL)ignoringAlerts
{
    UIViewController *viewController = self;
    while (YES) {
        UIViewController *_Nullable nextViewController = viewController.presentedViewController;
        if (nextViewController) {
            if (ignoringAlerts) {
                if ([nextViewController isKindOfClass:[UIAlertController class]]) {
                    break;
                }
            }
            viewController = nextViewController;
        } else if ([viewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navigationController = (UINavigationController *)viewController;
            if (navigationController.topViewController) {
                viewController = navigationController.topViewController;
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
    const CGFloat kExtraHeightPadding = 4;

    // Matching the default backbutton placement is tricky.
    // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
    // so we adjust the imageEdgeInsets on a UIButton, then wrap that
    // in a UIBarButtonItem.
    [backButton addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];

    UIImage *backImage = [[UIImage imageNamed:(isRTL ? @"NavBarBackRTL" : @"NavBarBack")]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssertDebug(backImage);
    [backButton setImage:backImage forState:UIControlStateNormal];
    backButton.tintColor = Theme.navbarIconColor;

    backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;

    // Default back button is 1.5 pixel lower than our extracted image.
    const CGFloat kTopInsetPadding = 1.5;
    backButton.imageEdgeInsets = UIEdgeInsetsMake(kTopInsetPadding, kExtraLeftPadding, 0, 0);

    CGRect buttonFrame
        = CGRectMake(0, 0, backImage.size.width + kExtraRightPadding, backImage.size.height + kExtraHeightPadding);
    backButton.frame = buttonFrame;

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 1)) {
        // In iOS 11.1 beta, the hot area of custom bar button items is _only_
        // the bounds of the custom view, making them very hard to hit.
        //
        // TODO: Remove this hack if the bug is fixed in iOS 11.1 by the time
        //       it goes to production (or in a later release),
        //       since it has two negative side effects: 1) the layout of the
        //       back button isn't consistent with the iOS default back buttons
        //       2) we can't add the unread count badge to the back button
        //       with this hack.
        return [[UIBarButtonItem alloc] initWithImage:backImage
                                                style:UIBarButtonItemStylePlain
                                               target:target
                                               action:selector];
    }

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];
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
