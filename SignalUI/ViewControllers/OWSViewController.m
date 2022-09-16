//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"
#import "Theme.h"
#import "UIView+SignalUI.h"
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController ()

@property (nonatomic, nullable, weak) UIView *bottomLayoutView;
@property (nonatomic, nullable) NSLayoutConstraint *bottomLayoutConstraint;
@property (nonatomic) BOOL shouldAnimateBottomLayout;
@property (nonatomic) BOOL hasObservedNotifications;
@property (nonatomic) CGFloat keyboardAdjustmentOffsetForAutoPinnedToBottomView;
@property (nonatomic) CGFloat lastBottomLayoutInset;

@end

#pragma mark -

@implementation OWSViewController

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    OWSLogVerbose(@"Dealloc: %@", self.class);
}

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) {
        self.shouldUseTheme = YES;
        return self;
    }

    [self observeActivation];

    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    self.shouldAnimateBottomLayout = YES;

#ifdef DEBUG
    [self ensureNavbarAccessibilityIds];
#endif
}

#ifdef DEBUG
- (void)ensureNavbarAccessibilityIds
{
    UINavigationBar *_Nullable navigationBar = self.navigationController.navigationBar;
    if (!navigationBar) {
        return;
    }
    // There isn't a great way to assign accessibilityIdentifiers to default
    // navbar buttons, e.g. the back button.  As a (DEBUG-only) hack, we
    // assign accessibilityIds to any navbar controls which don't already have
    // one.  This should offer a reliable way for automated scripts to find
    // these controls.
    //
    // UINavigationBar often discards and rebuilds new contents, e.g. between
    // presentations of the view, so we need to do this every time the view
    // appears.  We don't do any checking for accessibilityIdentifier collisions
    // so we're counting on the fact that navbar contents are short-lived.
    __block int accessibilityIdCounter = 0;
    [navigationBar traverseViewHierarchyDownwardWithVisitor:^(UIView *view) {
        if ([view isKindOfClass:[UIControl class]] && view.accessibilityIdentifier == nil) {
            // The view should probably be an instance of _UIButtonBarButton or _UIModernBarButton.
            view.accessibilityIdentifier = [NSString stringWithFormat:@"navbar-%d", accessibilityIdCounter];
            accessibilityIdCounter++;
        }
    }];
}
#endif

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    self.shouldAnimateBottomLayout = NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if (self.shouldUseTheme) {
        self.view.backgroundColor = Theme.backgroundColor;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

#pragma mark -

- (NSLayoutConstraint *)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch
{
    OWSAssertDebug(view);
    OWSAssertDebug(!self.bottomLayoutConstraint);

    [self observeNotificationsForBottomView];

    self.bottomLayoutView = view;
    if (avoidNotch) {
        self.bottomLayoutConstraint = [view autoPinToBottomLayoutGuideOfViewController:self
                                                                             withInset:self.lastBottomLayoutInset];
    } else {
        self.bottomLayoutConstraint = [view autoPinEdge:ALEdgeBottom
                                                 toEdge:ALEdgeBottom
                                                 ofView:self.view
                                             withOffset:self.lastBottomLayoutInset];
    }
    return self.bottomLayoutConstraint;
}

- (NSLayoutConstraint *)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view
                                                           avoidNotch:(BOOL)avoidNotch
                                      adjustmentWithKeyboardPresented:(CGFloat)adjustment
{
    self.keyboardAdjustmentOffsetForAutoPinnedToBottomView = adjustment;
    return [self autoPinViewToBottomOfViewControllerOrKeyboard:view avoidNotch:avoidNotch];
}

- (void)observeNotificationsForBottomView
{
    OWSAssertIsOnMainThread();

    if (self.hasObservedNotifications) {
        return;
    }
    self.hasObservedNotifications = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardNotificationBase:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];
}

- (void)removeBottomLayout
{
    [self.bottomLayoutConstraint autoRemove];
    self.bottomLayoutView = nil;
    self.bottomLayoutConstraint = nil;
}

- (void)observeActivation
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(owsViewControllerApplicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)owsViewControllerApplicationDidBecomeActive:(NSNotification *)notification
{
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)themeDidChange
{
    OWSAssertIsOnMainThread();

    [self applyTheme];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    // Do nothing; this is a convenience hook for subclasses.
}

// We use the name `handleKeyboardNotificationBase` instead of
// `handleKeyboardNotification` to avoid accidentally
// calling similarly methods with that name in subclasses,
// e.g. ConversationViewController.
- (void)handleKeyboardNotificationBase:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.shouldIgnoreKeyboardChanges) {
        return;
    }

    NSDictionary *userInfo = [notification userInfo];

    NSValue *_Nullable keyboardEndFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFailDebug(@"Missing keyboard end frame");
        return;
    }

    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];
    if (CGRectEqualToRect(keyboardEndFrame, CGRectZero)) {
        // If reduce motion+crossfade transitions is on, in iOS 14 UIKit vends out a keyboard end frame
        // of CGRect zero. This breaks the math below.
        //
        // If our keyboard end frame is CGRectZero, build a fake rect that's translated off the bottom edge.
        CGRect deviceBounds = UIScreen.mainScreen.bounds;
        keyboardEndFrame = CGRectOffset(deviceBounds, 0, deviceBounds.size.height);
    }

    CGRect keyboardEndFrameConverted = [self.view convertRect:keyboardEndFrame fromView:nil];
    // Adjust the position of the bottom view to account for the keyboard's
    // intrusion into the view.
    //
    // On iPhones with no physical home button, when no keyboard is present, we include a buffer at the bottom of the screen so the bottom view
    // clears the floating "home button". But because the keyboard includes it's own buffer, we subtract the size of bottom "safe area",
    // else we'd have an unnecessary buffer between the popped keyboard and the input bar.
    CGFloat newInset = MAX(0,
        (self.view.height + self.keyboardAdjustmentOffsetForAutoPinnedToBottomView - self.view.safeAreaInsets.bottom
            - keyboardEndFrameConverted.origin.y));
    self.lastBottomLayoutInset = newInset;

    UIViewAnimationCurve curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    // Should we ignore keyboard changes if they're coming from somewhere out-of-process?
    // BOOL isOurKeyboard = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];

    dispatch_block_t updateLayout = ^{
        if (self.shouldBottomViewReserveSpaceForKeyboard && newInset <= 0) {
            // To avoid unnecessary animations / layout jitter,
            // some views never reclaim layout space when the keyboard is dismissed.
            //
            // They _do_ need to relayout if the user switches keyboards.
            return;
        }
        [self updateBottomLayoutConstraintFromInset:-self.bottomLayoutConstraint.constant toInset:newInset];
    };


    if (self.shouldAnimateBottomLayout && duration > 0 && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView beginAnimations:@"keyboardStateChange" context:NULL];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationCurve:curve];
        [UIView setAnimationDuration:duration];
        updateLayout();
        [UIView commitAnimations];
    } else {
        // UIKit by default (sometimes? never?) animates all changes in response to keyboard events.
        // We want to suppress those animations if the view isn't visible,
        // otherwise presentation animations don't work properly.
        [UIView performWithoutAnimation:updateLayout];
    }
}

- (void)updateBottomLayoutConstraintFromInset:(CGFloat)before toInset:(CGFloat)after
{
    self.bottomLayoutConstraint.constant = -after;
    [self.bottomLayoutView.superview layoutIfNeeded];
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.defaultSupportedOrientations;
}

@end

NS_ASSUME_NONNULL_END
