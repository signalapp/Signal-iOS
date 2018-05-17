//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSNavigationController (OWSNavigationController) <UINavigationBarDelegate, NavBarLayoutDelegate>

@end

#pragma mark -

@interface OWSNavigationController () <UIGestureRecognizerDelegate>

@end

#pragma mark -

@implementation OWSNavigationController

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    //  Attempt 1: negative additionalSafeArea
    // Failure: additionalSafeArea insets cannot be negative
    //    UIEdgeInsets newSafeArea = UIEdgeInsetsMake(-50, 30, 20, 30);
    //    rootViewController.additionalSafeAreaInsets = newSafeArea;

    // Attempt 2: safeAreaInsets on vc.view
    // failure. they're already 0
    //    UIEdgeInsets existingInsets = rootViewController.view.safeAreaInsets;

    // Attempt 3: override topLayoutGuide?
    // Failure - not called.
    // overriding it does no good - it's not called by default layout code.
    // presumably it just existing if you want to use it as an anchor.

    // Attemp 4: sizeForChildContentConainer?
    // Failure - not called.

    // Attempt 5: autoSetDimension on navbar
    // Failure: no effect on rendered size

    // Attempt 6: manually set child frames in will/didLayoutSubviews
    // glitchy, and viewcontrollers re-layout themselves afterwards anyway

    // Attempt 7: Since we can't seem to *shrink* the navbar, maybe we can grow it.
    // make additionalSafeAreaInsets

    self = [self initWithNavigationBarClass:[OWSNavigationBar class] toolbarClass:nil];
    [self pushViewController:rootViewController animated:NO];

    if (![self.navigationBar isKindOfClass:[OWSNavigationBar class]]) {
        OWSFail(@"%@ navigationBar was unexpected class: %@", self.logTag, self.navigationBar);
        return self;
    }

    OWSNavigationBar *navbar = (OWSNavigationBar *)self.navigationBar;
    navbar.navBarLayoutDelegate = self;
    [self updateLayoutForNavbar:navbar];

    return self;
}

- (void)navBarCallLayoutDidChangeWithNavbar:(OWSNavigationBar *)navbar
{
    [self updateLayoutForNavbar:navbar];
}

- (void)updateLayoutForNavbar:(OWSNavigationBar *)navbar
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);

    if (@available(iOS 11.0, *)) {
        if (OWSWindowManager.sharedManager.hasCall) {
            self.additionalSafeAreaInsets = UIEdgeInsetsMake(64, 0, 0, 0);
        } else {
            self.additionalSafeAreaInsets = UIEdgeInsetsZero;
        }
        [navbar layoutSubviews];
    } else {
        // Pre iOS11 we have to position the frame manually
        [navbar sizeToFit];

        if (OWSWindowManager.sharedManager.hasCall) {
            CGRect oldFrame = navbar.frame;
            CGRect newFrame
                = CGRectMake(oldFrame.origin.x, navbar.callBannerHeight, oldFrame.size.width, oldFrame.size.height);
            navbar.frame = newFrame;
        } else {
            CGRect oldFrame = navbar.frame;
            CGRect newFrame
                = CGRectMake(oldFrame.origin.x, navbar.statusBarHeight, oldFrame.size.width, oldFrame.size.height);
            navbar.frame = newFrame;
        }

        // Since the navbar's frame was updated, we need to be sure our child VC's
        // container view is updated.
        [self.view setNeedsLayout];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    //    self.interactivePopGestureRecognizer.delegate = self;
}

#pragma mark - UINavigationBarDelegate

// All OWSNavigationController serve as the UINavigationBarDelegate for their navbar.
// We override shouldPopItem: in order to cancel some back button presses - for example,
// if a view has unsaved changes.
//- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item
//{
//    OWSAssert(self.interactivePopGestureRecognizer.delegate == self);
//    UIViewController *topViewController = self.topViewController;
//
//    // wasBackButtonClicked is YES if the back button was pressed but not
//    // if a back gesture was performed or if the view is popped programmatically.
//    BOOL wasBackButtonClicked = topViewController.navigationItem == item;
//    BOOL result = YES;
//    if (wasBackButtonClicked) {
//        if ([topViewController conformsToProtocol:@protocol(OWSNavigationView)]) {
//            id<OWSNavigationView> navigationView = (id<OWSNavigationView>)topViewController;
//            result = ![navigationView shouldCancelNavigationBack];
//        }
//    }
//
//    // If we're not going to cancel the pop/back, we need to call the super
//    // implementation since it has important side effects.
//    if (result) {
//        // NOTE: result might end up NO if the super implementation cancels the
//        //       the pop/back.
//
//        // MJK WTF?? This seems super broken. It won't compile now, but how could it ever
//        // have? This is a delegate method, so how are we calling it on super?
//        // [super navigationBar:navigationBar shouldPopItem:item];
//        result =  YES;
//    }
//    return result;
//}

#pragma mark - UIGestureRecognizerDelegate

// We serve as the UIGestureRecognizerDelegate of the interactivePopGestureRecognizer
// in order to cancel some "back" gestures - for example,
// if a view has unsaved changes.
//- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
//{
//    UIViewController *topViewController = self.topViewController;
//    if ([topViewController conformsToProtocol:@protocol(OWSNavigationView)]) {
//        id<OWSNavigationView> navigationView = (id<OWSNavigationView>)topViewController;
//        return ![navigationView shouldCancelNavigationBack];
//    } else {
//        return YES;
//    }
//}

@end

NS_ASSUME_NONNULL_END
