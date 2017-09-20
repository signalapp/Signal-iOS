//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSNavigationController.h"

// We use a category to expose UINavigationController's private
// UINavigationBarDelegate methods.
@interface UINavigationController (OWSNavigationController) <UINavigationBarDelegate>

@end

#pragma mark -

@interface OWSNavigationController () <UIGestureRecognizerDelegate>

@end

#pragma mark -

@implementation OWSNavigationController

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
