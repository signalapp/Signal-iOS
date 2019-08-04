//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import "Environment.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSWindowManagerCallDidChangeNotification = @"OWSWindowManagerCallDidChangeNotification";

NSString *const IsScreenBlockActiveDidChangeNotification = @"IsScreenBlockActiveDidChangeNotification";

const CGFloat OWSWindowManagerCallBannerHeight(void)
{
    if (@available(iOS 11.4, *)) {
        return CurrentAppContext().statusBarHeight + 20;
    }

    if (![UIDevice currentDevice].hasIPhoneXNotch) {
        return CurrentAppContext().statusBarHeight + 20;
    }

    // Hardcode CallBanner height for iPhone X's on older iOS.
    //
    // As of iOS11.4 and iOS12, this no longer seems to be an issue, but previously statusBarHeight returned
    // something like 20pts (IIRC), meaning our call banner did not extend sufficiently past the iPhone X notch.
    //
    // Before noticing that this behavior changed, I actually assumed that notch height was intentionally excluded from
    // the statusBarHeight, and that this was not a bug, else I'd have taken better notes.
    return 64;
}

// Behind everything, especially the root window.
const UIWindowLevel UIWindowLevel_Background = -1.f;

const UIWindowLevel UIWindowLevel_ReturnToCall(void);
const UIWindowLevel UIWindowLevel_ReturnToCall(void)
{
    return UIWindowLevelStatusBar - 1;
}

// In front of the root window, behind the screen blocking window.
const UIWindowLevel UIWindowLevel_CallView(void);
const UIWindowLevel UIWindowLevel_CallView(void)
{
    return UIWindowLevelNormal + 1.f;
}

// In front of the status bar and CallView
const UIWindowLevel UIWindowLevel_ScreenBlocking(void);
const UIWindowLevel UIWindowLevel_ScreenBlocking(void)
{
    return UIWindowLevelStatusBar + 2.f;
}

// In front of everything
const UIWindowLevel UIWindowLevel_MessageActions(void);
const UIWindowLevel UIWindowLevel_MessageActions(void)
{
    // Note: To cover the keyboard, this is higher than the ScreenBlocking level,
    // but this window is hidden when screen protection is shown.
    return CGFLOAT_MAX - 100;
}

#pragma mark -

@interface MessageActionsWindow : UIWindow

@end

#pragma mark -

@implementation MessageActionsWindow

- (UIWindowLevel)windowLevel
{
    // As of iOS11, setWindowLevel clamps the value below
    // the height of the keyboard window.
    // Because we want to display above the keyboard, we hardcode
    // the `windowLevel` getter.
    return UIWindowLevel_MessageActions();
}

@end

#pragma mark -

@implementation OWSWindowRootViewController

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end

#pragma mark -

@interface OWSWindowRootNavigationViewController : UINavigationController

@end

#pragma mark -

@implementation OWSWindowRootNavigationViewController : UINavigationController

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end

#pragma mark -

@interface OWSWindowManager () <ReturnToCallViewControllerDelegate>

// UIWindowLevelNormal
@property (nonatomic) UIWindow *rootWindow;

// UIWindowLevel_ReturnToCall
@property (nonatomic) UIWindow *returnToCallWindow;
@property (nonatomic) ReturnToCallViewController *returnToCallViewController;

// UIWindowLevel_CallView
@property (nonatomic) UIWindow *callViewWindow;
@property (nonatomic) UINavigationController *callNavigationController;

// UIWindowLevel_MessageActions
@property (nonatomic) UIWindow *menuActionsWindow;
@property (nonatomic, nullable) UIViewController *menuActionsViewController;

// UIWindowLevel_Background if inactive,
// UIWindowLevel_ScreenBlocking() if active.
@property (nonatomic) UIWindow *screenBlockingWindow;

@property (nonatomic) BOOL shouldShowCallView;

@property (nonatomic, nullable) UIViewController *callViewController;

@end

#pragma mark -

@implementation OWSWindowManager

+ (instancetype)sharedManager
{
    OWSAssertDebug(Environment.shared.windowManager);

    return Environment.shared.windowManager;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSSingletonAssert();

    return self;
}

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);
    OWSAssertDebug(!self.rootWindow);
    OWSAssertDebug(screenBlockingWindow);
    OWSAssertDebug(!self.screenBlockingWindow);

    self.rootWindow = rootWindow;
    self.screenBlockingWindow = screenBlockingWindow;

    self.returnToCallWindow = [self createReturnToCallWindow:rootWindow];
    self.callViewWindow = [self createCallViewWindow:rootWindow];
    self.menuActionsWindow = [self createMenuActionsWindowWithRoowWindow:rootWindow];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeStatusBarFrame:)
                                                 name:UIApplicationDidChangeStatusBarFrameNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];

    [self ensureWindowState];
}

- (void)didChangeStatusBarFrame:(NSNotification *)notification
{
    // Apple bug? Upon returning from landscape, this method *is* fired, but both the notification and [UIApplication
    // sharedApplication].statusBarFrame still show a height of 0. So to work around we also call
    // `ensureReturnToCallWindowFrame` before showing the call banner.
    [self ensureReturnToCallWindowFrame];
}

- (void)ensureReturnToCallWindowFrame
{
    CGRect newFrame = self.returnToCallWindow.frame;
    newFrame.size.height = OWSWindowManagerCallBannerHeight();
    OWSLogDebug(@"returnToCallWindowFrame: %@", NSStringFromCGRect(newFrame));
    self.returnToCallWindow.frame = newFrame;
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self hideMenuActionsWindow];
}

- (UIWindow *)createReturnToCallWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    // "Return to call" should remain at the top of the screen.
    CGRect windowFrame = UIScreen.mainScreen.bounds;
    windowFrame.size.height = OWSWindowManagerCallBannerHeight();
    UIWindow *window = [[UIWindow alloc] initWithFrame:windowFrame];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_ReturnToCall();
    window.opaque = YES;

    ReturnToCallViewController *viewController = [ReturnToCallViewController new];
    self.returnToCallViewController = viewController;
    viewController.delegate = self;

    window.rootViewController = viewController;

    return window;
}

- (UIWindow *)createMenuActionsWindowWithRoowWindow:(UIWindow *)rootWindow
{
    UIWindow *window;
    if (@available(iOS 11, *)) {
        // On iOS11, setting the windowLevel is insufficient, so we override
        // the `windowLevel` getter.
        window = [[MessageActionsWindow alloc] initWithFrame:rootWindow.bounds];
    } else {
        // On iOS9, 10 overriding the `windowLevel` getter does not cause the
        // window to be displayed above the keyboard, but setting the window
        // level works.
        window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
        window.windowLevel = UIWindowLevel_MessageActions();
    }

    window.hidden = YES;
    window.backgroundColor = UIColor.clearColor;

    return window;
}

- (UIWindow *)createCallViewWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_CallView();
    window.opaque = YES;
    // TODO: What's the right color to use here?
    window.backgroundColor = [UIColor ows_materialBlueColor];

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = [UIColor ows_materialBlueColor];

    // NOTE: Do not use OWSNavigationController for call window.
    // It adjusts the size of the navigation bar to reflect the
    // call window.  We don't want those adjustments made within
    // the call window itself.
    OWSWindowRootNavigationViewController *navigationController =
        [[OWSWindowRootNavigationViewController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;
    OWSAssertDebug(!self.callNavigationController);
    self.callNavigationController = navigationController;

    window.rootViewController = navigationController;

    return window;
}

- (void)setIsScreenBlockActive:(BOOL)isScreenBlockActive
{
    OWSAssertIsOnMainThread();

    _isScreenBlockActive = isScreenBlockActive;

    [self ensureWindowState];

    [[NSNotificationCenter defaultCenter] postNotificationName:IsScreenBlockActiveDidChangeNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (BOOL)isAppWindow:(UIWindow *)window
{
    OWSAssertDebug(window);

    return (window == self.rootWindow || window == self.returnToCallWindow || window == self.callViewWindow
        || window == self.menuActionsWindow || window == self.screenBlockingWindow);
}

- (void)updateWindowFrames
{
    OWSAssertIsOnMainThread();

    CGRect windowFrame = [[UIScreen mainScreen] bounds];
    for (UIWindow *window in @[
             self.rootWindow,
             self.callViewWindow,
             self.screenBlockingWindow,
         ]) {
        if (!CGRectEqualToRect(window.frame, windowFrame)) {
            window.frame = windowFrame;
        }
    }
}

#pragma mark - Message Actions

- (BOOL)isPresentingMenuActions
{
    return self.menuActionsViewController != nil;
}

- (void)showMenuActionsWindow:(UIViewController *)menuActionsViewController
{
    OWSAssertDebug(self.menuActionsViewController == nil);

    self.menuActionsViewController = menuActionsViewController;
    self.menuActionsWindow.rootViewController = menuActionsViewController;

    [self ensureWindowState];
}

- (void)hideMenuActionsWindow
{
    self.menuActionsWindow.rootViewController = nil;
    self.menuActionsViewController = nil;

    [self ensureWindowState];
}

#pragma mark - Calls

- (void)setCallViewController:(nullable UIViewController *)callViewController
{
    OWSAssertIsOnMainThread();

    if (callViewController == _callViewController) {
        return;
    }

    _callViewController = callViewController;

    [NSNotificationCenter.defaultCenter postNotificationName:OWSWindowManagerCallDidChangeNotification object:nil];
}

- (void)startCall:(UIViewController *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(callViewController);
    OWSAssertDebug(!self.callViewController);

    self.callViewController = callViewController;

    // Attach callViewController to window.
    [self.callNavigationController popToRootViewControllerAnimated:NO];
    [self.callNavigationController pushViewController:callViewController animated:NO];
    self.shouldShowCallView = YES;
    // CallViewController only supports portrait, but if we're _already_ landscape it won't
    // automatically switch.
    [UIDevice.currentDevice ows_setOrientation:UIInterfaceOrientationPortrait];
    [self ensureWindowState];
}

- (void)endCall:(UIViewController *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(callViewController);
    OWSAssertDebug(self.callViewController);

    if (self.callViewController != callViewController) {
        OWSLogWarn(@"Ignoring end call request from obsolete call view controller.");
        return;
    }

    // Dettach callViewController from window.
    [self.callNavigationController popToRootViewControllerAnimated:NO];
    self.callViewController = nil;

    self.shouldShowCallView = NO;

    [self ensureWindowState];
}

- (void)leaveCallView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.callViewController);
    OWSAssertDebug(self.shouldShowCallView);

    self.shouldShowCallView = NO;

    [self ensureWindowState];
}

- (void)showCallView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.callViewController);
    OWSAssertDebug(!self.shouldShowCallView);

    self.shouldShowCallView = YES;

    [self ensureWindowState];
}

- (BOOL)hasCall
{
    OWSAssertIsOnMainThread();

    return self.callViewController != nil;
}

#pragma mark - Window State

- (void)ensureWindowState
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.rootWindow);
    OWSAssertDebug(self.returnToCallWindow);
    OWSAssertDebug(self.callViewWindow);
    OWSAssertDebug(self.screenBlockingWindow);

    // To avoid bad frames, we never want to hide the blocking window, so we manipulate
    // its window level to "hide" it behind other windows.  The other windows have fixed
    // window level and are shown/hidden as necessary.
    //
    // Note that we always "hide" before we "show".
    if (self.isScreenBlockActive) {
        // Show Screen Block.

        [self ensureRootWindowHidden];
        [self ensureReturnToCallWindowHidden];
        [self ensureCallViewWindowHidden];
        [self ensureMessageActionsWindowHidden];
        [self ensureScreenBlockWindowShown];
    } else if (self.callViewController && self.shouldShowCallView) {
        // Show Call View.

        [self ensureRootWindowHidden];
        [self ensureReturnToCallWindowHidden];
        [self ensureCallViewWindowShown];
        [self ensureMessageActionsWindowHidden];
        [self ensureScreenBlockWindowHidden];
    } else {
        // Show Root Window

        [self ensureRootWindowShown];
        [self ensureCallViewWindowHidden];
        [self ensureScreenBlockWindowHidden];

        if (self.callViewController) {
            // Add "Return to Call" banner

            [self ensureReturnToCallWindowShown];
        } else {
            [self ensureReturnToCallWindowHidden];
        }

        if (self.menuActionsViewController) {
            // Add "Message Actions" action sheet

            [self ensureMessageActionsWindowShown];

            // Don't hide rootWindow so as not to dismiss keyboard.
            OWSAssertDebug(!self.rootWindow.isHidden);
        } else {
            [self ensureMessageActionsWindowHidden];
        }
    }
}

- (void)ensureRootWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.rootWindow.hidden) {
        OWSLogInfo(@"showing root window.");
    }

    // By calling makeKeyAndVisible we ensure the rootViewController becomes first responder.
    // In the normal case, that means the SignalViewController will call `becomeFirstResponder`
    // on the vc on top of its navigation stack.
    [self.rootWindow makeKeyAndVisible];

    [self fixit_workAroundRotationIssue];
}

- (void)ensureRootWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.rootWindow.hidden) {
        OWSLogInfo(@"hiding root window.");
    }

    self.rootWindow.hidden = YES;
}

- (void)ensureReturnToCallWindowShown
{
    OWSAssertIsOnMainThread();

    if (!self.returnToCallWindow.hidden) {
        return;
    }

    [self ensureReturnToCallWindowFrame];
    OWSLogInfo(@"showing 'return to call' window.");
    self.returnToCallWindow.hidden = NO;
    [self.returnToCallViewController startAnimating];
}

- (void)ensureReturnToCallWindowHidden
{
    OWSAssertIsOnMainThread();

    if (self.returnToCallWindow.hidden) {
        return;
    }

    OWSLogInfo(@"hiding 'return to call' window.");
    self.returnToCallWindow.hidden = YES;
    [self.returnToCallViewController stopAnimating];
}

- (void)ensureCallViewWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.callViewWindow.hidden) {
        OWSLogInfo(@"showing call window.");
    }

    [self.callViewWindow makeKeyAndVisible];
}

- (void)ensureCallViewWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.callViewWindow.hidden) {
        OWSLogInfo(@"hiding call window.");
    }

    self.callViewWindow.hidden = YES;
}

- (void)ensureMessageActionsWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.menuActionsWindow.hidden) {
        OWSLogInfo(@"showing message actions window.");
    }

    // Do not make key, we want the keyboard to stay popped.
    self.menuActionsWindow.hidden = NO;
}

- (void)ensureMessageActionsWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.menuActionsWindow.hidden) {
        OWSLogInfo(@"hiding message actions window.");
    }

    self.menuActionsWindow.hidden = YES;
}

- (void)ensureScreenBlockWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_ScreenBlocking()) {
        OWSLogInfo(@"showing block window.");
    }

    self.screenBlockingWindow.windowLevel = UIWindowLevel_ScreenBlocking();
    [self.screenBlockingWindow makeKeyAndVisible];
}

- (void)ensureScreenBlockWindowHidden
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_Background) {
        OWSLogInfo(@"hiding block window.");
    }

    // Never hide the blocking window (that can lead to bad frames).
    // Instead, manipulate its window level to move it in front of
    // or behind the root window.
    self.screenBlockingWindow.windowLevel = UIWindowLevel_Background;
}

#pragma mark - ReturnToCallViewControllerDelegate

- (void)returnToCallWasTapped:(ReturnToCallViewController *)viewController
{
    [self showCallView];
}

#pragma mark - Fixit

- (void)fixit_workAroundRotationIssue
{
    // ### Symptom
    //
    // The app can get into a degraded state where the main window will incorrectly remain locked in
    // portrait mode. Worse yet, the status bar and input window will continue to rotate with respect
    // to the device orientation. So once you're in this degraded state, the status bar and input
    // window can be in landscape while simultaneoulsy the view controller behind them is in portrait.
    //
    // ### To Reproduce
    //
    // On an iPhone6 (not reproducible on an iPhoneX)
    //
    // 0. Ensure "screen protection" is enabled (not necessarily screen lock)
    // 1. Enter Conversation View Controller
    // 2. Pop Keyboard
    // 3. Begin dismissing keyboard with one finger, but stopping when it's about 50% dismissed,
    //    keep your finger there with the keyboard partially dismissed.
    // 4. With your other hand, hit the home button to leave Signal.
    // 5. Re-enter Signal
    // 6. Rotate to landscape
    //
    // Expected: Conversation View, Input Toolbar window, and Settings Bar should all rotate to landscape.
    // Actual: The input toolbar and the settings toolbar rotate to landscape, but the Conversation
    //         View remains in portrait, this looks super broken.
    //
    // ### Background
    //
    // Some debugging shows that the `ConversationViewController.view.window.isInterfaceAutorotationDisabled`
    // is true. This is a private property, whose function we don't exactly know, but it seems like
    // `interfaceAutorotation` is disabled when certain transition animations begin, and then
    // re-enabled once the animation completes.
    //
    // My best guess is that autorotation is intended to be disabled for the duration of the
    // interactive-keyboard-dismiss-transition, so when we start the interactive dismiss, autorotation
    // has been disabled, but because we hide the main app window in the middle of the transition,
    // autorotation doesn't have a chance to be re-enabled.
    //
    // ## So, The Fix
    //
    // If we find ourself in a situation where autorotation is disabled while showing the rootWindow,
    // we re-enable autorotation.

    // NSString *encodedSelectorString1 = @"isInterfaceAutorotationDisabled".encodedForSelector;
    NSString *encodedSelectorString1 = @"egVaAAZ2BHdydHZSBwYBBAEGcgZ6AQBVegVyc312dQ==";
    NSString *_Nullable selectorString1 = encodedSelectorString1.decodedForSelector;
    if (selectorString1 == nil) {
        OWSFailDebug(@"selectorString1 was unexpectedly nil");
        return;
    }
    SEL selector1 = NSSelectorFromString(selectorString1);

    if (![self.rootWindow respondsToSelector:selector1]) {
        OWSFailDebug(@"failure: doesn't respond to selector1");
        return;
    }
    IMP imp1 = [self.rootWindow methodForSelector:selector1];
    BOOL (*func1)(id, SEL) = (void *)imp1;
    BOOL isDisabled = func1(self.rootWindow, selector1);

    if (isDisabled) {
        OWSLogInfo(@"autorotation is disabled.");

        // The remainder of this method calls:
        //   [[UIScrollToDismissSupport supportForScreen:UIScreen.main] finishScrollViewTransition]
        // after verifying the methods/classes exist.

        // NSString *encodedKlassString = @"UIScrollToDismissSupport".encodedForSelector;
        NSString *encodedKlassString = @"ZlpkdAQBfX1lAVV6BX56BQVkBwICAQQG";
        NSString *_Nullable klassString = encodedKlassString.decodedForSelector;
        if (klassString == nil) {
            OWSFailDebug(@"klassString was unexpectedly nil");
            return;
        }
        id klass = NSClassFromString(klassString);
        if (klass == nil) {
            OWSFailDebug(@"klass was unexpectedly nil");
            return;
        }

        // NSString *encodedSelector2String = @"supportForScreen:".encodedForSelector;
        NSString *encodedSelector2String = @"BQcCAgEEBlcBBGR0BHZ2AEs=";
        NSString *_Nullable selector2String = encodedSelector2String.decodedForSelector;
        if (selector2String == nil) {
            OWSFailDebug(@"selector2String was unexpectedly nil");
            return;
        }
        SEL selector2 = NSSelectorFromString(selector2String);
        if (![klass respondsToSelector:selector2]) {
            OWSFailDebug(@"klass didn't respond to selector");
            return;
        }
        IMP imp2 = [klass methodForSelector:selector2];
        id (*func2)(id, SEL, UIScreen *) = (void *)imp2;
        id dismissSupport = func2(klass, selector2, UIScreen.mainScreen);

        // NSString *encodedSelector3String = @"finishScrollViewTransition".encodedForSelector;
        NSString *encodedSelector3String = @"d3oAegV5ZHQEAX19Z3p2CWUEcgAFegZ6AQA=";
        NSString *_Nullable selector3String = encodedSelector3String.decodedForSelector;
        if (selector3String == nil) {
            OWSFailDebug(@"selector3String was unexpectedly nil");
            return;
        }
        SEL selector3 = NSSelectorFromString(selector3String);
        if (![dismissSupport respondsToSelector:selector3]) {
            OWSFailDebug(@"dismissSupport didn't respond to selector");
            return;
        }
        IMP imp3 = [dismissSupport methodForSelector:selector3];
        void (*func3)(id, SEL) = (void *)imp3;
        func3(dismissSupport, selector3);

        OWSLogInfo(@"finished scrollView transition");
    }
}

@end

NS_ASSUME_NONNULL_END
