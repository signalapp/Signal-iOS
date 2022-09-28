//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppContext.h"
#import "OWSNavigationController.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUIKit/SessionUIKit.h>

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
    self = [super initWithNavigationBarClass:[OWSNavigationBar class] toolbarClass:nil];
    if (!self) {
        return self;
    }
    [self setupNavbar];

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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

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
        return LKAppModeUtilities.isLightMode ? UIStatusBarStyleDefault : UIStatusBarStyleLightContent;
    }
}

- (void)updateLayoutForNavbar:(OWSNavigationBar *)navbar
{
    OWSLogDebug(@"");

    [UIView setAnimationsEnabled:NO];
    
    if (!CurrentAppContext().isMainApp) {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    } else if (OWSWindowManager.sharedManager.hasCall) {
        self.additionalSafeAreaInsets = UIEdgeInsetsMake(20, 0, 0, 0);
    } else {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
    
    [navbar layoutSubviews];
    [UIView setAnimationsEnabled:YES];
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
