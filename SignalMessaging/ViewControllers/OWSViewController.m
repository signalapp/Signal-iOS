//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/Theme.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController ()

@property (nonatomic, weak) UIView *bottomLayoutView;
@property (nonatomic) NSLayoutConstraint *bottomLayoutConstraint;
@property (nonatomic) BOOL shouldAnimateBottomLayout;

@end

#pragma mark -

@implementation OWSViewController

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
}

#pragma mark -

- (void)autoPinViewToBottomOfViewControllerOrKeyboard:(UIView *)view avoidNotch:(BOOL)avoidNotch
{
    OWSAssertDebug(view);
    OWSAssertDebug(!self.bottomLayoutConstraint);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidChangeFrame:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];

    self.bottomLayoutView = view;
    if (avoidNotch) {
        self.bottomLayoutConstraint = [view autoPinToBottomLayoutGuideOfViewController:self withInset:0.f];
    } else {
        self.bottomLayoutConstraint = [view autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.view];
    }
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

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
}

- (void)keyboardDidShow:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotificationBase:notification];
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
    CGRect keyboardEndFrameConverted = [self.view convertRect:keyboardEndFrame fromView:nil];
    // Adjust the position of the bottom view to account for the keyboard's
    // intrusion into the view.
    //
    // On iPhoneX, when no keyboard is present, we include a buffer at the bottom of the screen so the bottom view
    // clears the floating "home button". But because the keyboard includes it's own buffer, we subtract the length
    // (height) of the bottomLayoutGuide, else we'd have an unnecessary buffer between the popped keyboard and the input
    // bar.
    CGFloat offset = -MAX(0, (self.view.height - self.bottomLayoutGuide.length - keyboardEndFrameConverted.origin.y));

    dispatch_block_t updateLayout = ^{
        if (self.shouldBottomViewReserveSpaceForKeyboard && offset >= 0) {
            // To avoid unnecessary animations / layout jitter,
            // some views never reclaim layout space when the keyboard is dismissed.
            //
            // They _do_ need to relayout if the user switches keyboards.
            return;
        }
        self.bottomLayoutConstraint.constant = offset;
        [self.bottomLayoutView.superview layoutIfNeeded];
    };


    if (self.shouldAnimateBottomLayout && CurrentAppContext().isAppForegroundAndActive) {
        updateLayout();
    } else {
        // UIKit by default animates all changes in response to keyboard events.
        // We want to suppress those animations if the view isn't visible,
        // otherwise presentation animations don't work properly.
        [UIView performWithoutAnimation:updateLayout];
    }
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.defaultSupportedOrienations;
}

@end

NS_ASSUME_NONNULL_END
