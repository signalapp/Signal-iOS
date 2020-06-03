//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Any view controller which wants to be able cancel back button
// presses and back gestures should implement this protocol.
@protocol OWSNavigationView <NSObject>

// shouldCancelNavigationBack will be called if the back button was pressed or
// if a back gesture was performed but not if the view is popped programmatically.
- (BOOL)shouldCancelNavigationBack;

@end

#pragma mark -

// This navigation controller subclass should be used anywhere we might
// want to cancel back button presses or back gestures due to, for example,
// unsaved changes.
@interface OWSNavigationController : UINavigationController

// If set, this property lets us override prefersStatusBarHidden behavior.
// This is useful for supressing the status bar while a modal is presented,
// regardless of which view is currently visible.
@property (nonatomic, nullable) NSNumber *ows_prefersStatusBarHidden;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNavigationBarClass:(nullable Class)navigationBarClass
                              toolbarClass:(nullable Class)toolbarClass NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// Convenience initializer which is neither "designated" nor "unavailable".
- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;

@end

NS_ASSUME_NONNULL_END
