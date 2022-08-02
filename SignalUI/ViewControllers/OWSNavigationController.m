//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface UINavigationController (OWSNavigationController) <UINavigationBarDelegate>

@end

#pragma mark -

// Expose that UINavigationController already secretly implements UIGestureRecognizerDelegate
// so we can call [super navigationBar:shouldPopItem] in our own implementation to take advantage
// of the important side effects of that method.
@interface OWSNavigationController () <UIGestureRecognizerDelegate>

@end

#pragma mark -

@implementation OWSNavigationController

- (instancetype)init
{
    self = [super initWithNavigationBarClass:[OWSNavigationBar class] toolbarClass:nil];
    if (!self) {
        return self;
    }

    self.ows_preferredStatusBarStyle = UIStatusBarStyleDefault;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];

    return self;
}

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    self = [self init];
    if (!self) {
        return self;
    }
    [self pushViewController:rootViewController animated:NO];

    return self;
}

#pragma mark -

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.navigationBar.barTintColor = [UINavigationBar appearance].barTintColor;
    self.navigationBar.tintColor = [UINavigationBar appearance].tintColor;
    self.navigationBar.titleTextAttributes = [UINavigationBar appearance].titleTextAttributes;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.interactivePopGestureRecognizer.delegate = self;
}

- (BOOL)prefersStatusBarHidden
{
    if (self.ows_prefersStatusBarHidden) {
        return self.ows_prefersStatusBarHidden.boolValue;
    }
    return [super prefersStatusBarHidden];
}

// All OWSNavigationController serve as the UINavigationBarDelegate for their navbar.
// We override shouldPopItem: in order to cancel some back button presses - for example,
// if a view has unsaved changes.
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item
{
    OWSAssertDebug(self.interactivePopGestureRecognizer.delegate == self);
    UIViewController *topViewController = self.topViewController;

    // wasBackButtonClicked is YES if the back button was pressed but not
    // if a back gesture was performed or if the view is popped programmatically.
    BOOL wasBackButtonClicked = topViewController.navigationItem == item;
    BOOL result = YES;
    if (wasBackButtonClicked) {
        if ([topViewController conformsToProtocol:@protocol(OWSNavigationView)]) {
            id<OWSNavigationView> navigationView = (id<OWSNavigationView>)topViewController;
            result = ![navigationView shouldCancelNavigationBack];
        }
    }

    // If we're not going to cancel the pop/back, we need to call the super
    // implementation since it has important side effects.
    if (result) {
        // NOTE: result might end up NO if the super implementation cancels the
        //       the pop/back.
        [super navigationBar:navigationBar shouldPopItem:item];
        result = YES;
    }
    return result;
}

#pragma mark - UIGestureRecognizerDelegate

// We serve as the UIGestureRecognizerDelegate of the interactivePopGestureRecognizer
// in order to cancel some "back" gestures - for example,
// if a view has unsaved changes.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    OWSAssertDebug(gestureRecognizer == self.interactivePopGestureRecognizer);

    UIViewController *topViewController = self.topViewController;
    if ([topViewController conformsToProtocol:@protocol(OWSNavigationView)]) {
        id<OWSNavigationView> navigationView = (id<OWSNavigationView>)topViewController;
        return ![navigationView shouldCancelNavigationBack];
    } else {
        UIViewController *rootViewController = self.viewControllers.firstObject;
        if (topViewController == rootViewController) {
            return NO;
        } else {
            return YES;
        }
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    if (self.ows_preferredStatusBarStyle != UIStatusBarStyleDefault) {
        return self.ows_preferredStatusBarStyle;
    }
    if (!CurrentAppContext().isMainApp) {
        return super.preferredStatusBarStyle;
    } else {
        UIViewController *presentedViewController = self.presentedViewController;
        if (presentedViewController != nil && !presentedViewController.isBeingDismissed) {
            return presentedViewController.preferredStatusBarStyle;
        } else if (@available(iOS 13, *)) {
            return (Theme.isDarkThemeEnabled ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent);
        } else {
            return (Theme.isDarkThemeEnabled ? UIStatusBarStyleLightContent : super.preferredStatusBarStyle);
        }
    }
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (self.delegate != nil &&
        [self.delegate respondsToSelector:@selector(navigationControllerSupportedInterfaceOrientations:)]) {
        return [self.delegate navigationControllerSupportedInterfaceOrientations:self];
    } else if (self.visibleViewController) {
        return self.visibleViewController.supportedInterfaceOrientations;
    } else {
        return UIDevice.currentDevice.defaultSupportedOrientations;
    }
}

@end

NS_ASSUME_NONNULL_END
