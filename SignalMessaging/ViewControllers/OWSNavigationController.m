//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface UINavigationController (OWSNavigationController) <UINavigationBarDelegate, NavBarLayoutDelegate>

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
    return [self initWithOWSNavbar];
}

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{

    self = [self initWithOWSNavbar];
    if (!self) {
        return self;
    }
    [self pushViewController:rootViewController animated:NO];

    return self;
}

- (instancetype)initWithOWSNavbar
{
    self = [super initWithNavigationBarClass:[OWSNavigationBar class] toolbarClass:nil];
    if (!self) {
        return self;
    }
    [self setupNavbar];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - UINavigationBarDelegate

- (void)setupNavbar
{
    if (![self.navigationBar isKindOfClass:[OWSNavigationBar class]]) {
        OWSFailDebug(@"navigationBar was unexpected class: %@", self.navigationBar);
        return;
    }
    OWSNavigationBar *navbar = (OWSNavigationBar *)self.navigationBar;
    navbar.navBarLayoutDelegate = self;
    [self updateLayoutForNavbar:navbar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
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
        result =  YES;
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

#pragma mark - NavBarLayoutDelegate

- (void)navBarCallLayoutDidChangeWithNavbar:(OWSNavigationBar *)navbar
{
    [self updateLayoutForNavbar:navbar];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    if (!CurrentAppContext().isMainApp) {
        return super.preferredStatusBarStyle;
    } else if (OWSWindowManager.sharedManager.hasCall) {
        // Status bar is overlaying the green "call banner"
        return UIStatusBarStyleLightContent;
    } else {
        UIViewController *presentedViewController = self.presentedViewController;
        if (presentedViewController != nil && !presentedViewController.isBeingDismissed) {
            return presentedViewController.preferredStatusBarStyle;
        } else {
            return (Theme.isDarkThemeEnabled ? UIStatusBarStyleLightContent : super.preferredStatusBarStyle);
        }
    }
}

- (void)updateLayoutForNavbar:(OWSNavigationBar *)navbar
{
    OWSLogDebug(@"");

    [UIView setAnimationsEnabled:NO];

    if (@available(iOS 11.0, *)) {
        if (!CurrentAppContext().isMainApp) {
            self.additionalSafeAreaInsets = UIEdgeInsetsZero;
        } else if (OWSWindowManager.sharedManager.hasCall) {
            self.additionalSafeAreaInsets = UIEdgeInsetsMake(20, 0, 0, 0);
        } else {
            self.additionalSafeAreaInsets = UIEdgeInsetsZero;
        }

        // in iOS11 we have to ensure the navbar frame *in* layoutSubviews.
        [navbar layoutSubviews];
    } else {
        // in iOS9/10 we only need to size the navbar once
        [navbar sizeToFit];
        [navbar layoutIfNeeded];

        // Since the navbar's frame was updated, we need to be sure our child VC's
        // container view is updated.
        [self.view setNeedsLayout];
        [self.view layoutSubviews];
    }
    [UIView setAnimationsEnabled:YES];
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (self.visibleViewController) {
        if (@available(iOS 10, *)) {
            // do nothing
        } else {
            // Avoid crash in SAE on iOS9
            if (!CurrentAppContext().isMainApp) {
                return UIInterfaceOrientationMaskAllButUpsideDown;
            }
        }
        return self.visibleViewController.supportedInterfaceOrientations;
    } else {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
}

@end

NS_ASSUME_NONNULL_END
