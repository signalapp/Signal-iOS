//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"
#import "Signal-Swift.h"

// We use a category to expose UINavigationController's private
// UINavigationBarDelegate methods.
@interface UINavigationController (OWSNavigationController) <UINavigationBarDelegate>

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
    
    [self updateAdditionalSafeAreaInsets];
    
    self = [self initWithNavigationBarClass:[SignalNavigationBar class] toolbarClass:nil];
    [self pushViewController:rootViewController animated:NO];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowManagerCallDidChange:)
                                                 name:OWSWindowManagerCallDidChangeNotification
                                               object:nil];
    
    return self;
}

- (void)windowManagerCallDidChange:(NSNotification *)notification
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [self updateAdditionalSafeAreaInsets];
}

- (void)updateAdditionalSafeAreaInsets
{
    if (OWSWindowManager.sharedManager.hasCall) {
        self.additionalSafeAreaInsets = UIEdgeInsetsMake(64, 0, 0, 0);
    } else {
        self.additionalSafeAreaInsets = UIEdgeInsetsZero;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.interactivePopGestureRecognizer.delegate = self;
}

#pragma mark - UINavigationBarDelegate

// All UINavigationController serve as the UINavigationBarDelegate for their navbar.
// We override shouldPopItem: in order to cancel some back button presses - for example,
// if a view has unsaved changes.
- (BOOL)navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item
{
    OWSAssert(self.interactivePopGestureRecognizer.delegate == self);
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
        result = [super navigationBar:navigationBar shouldPopItem:item];
    }
    return result;
}

#pragma mark - UIGestureRecognizerDelegate

// We serve as the UIGestureRecognizerDelegate of the interactivePopGestureRecognizer
// in order to cancel some "back" gestures - for example,
// if a view has unsaved changes.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    UIViewController *topViewController = self.topViewController;
    if ([topViewController conformsToProtocol:@protocol(OWSNavigationView)]) {
        id<OWSNavigationView> navigationView = (id<OWSNavigationView>)topViewController;
        return ![navigationView shouldCancelNavigationBack];
    } else {
        return YES;
    }
}

@end
