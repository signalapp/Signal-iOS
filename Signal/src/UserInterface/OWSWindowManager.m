//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalUI/SignalUI-Swift.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const IsScreenBlockActiveDidChangeNotification = @"IsScreenBlockActiveDidChangeNotification";

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
    return UIWindowLevelNormal + 2.f;
}

// In front of the status bar and CallView
const UIWindowLevel UIWindowLevel_ScreenBlocking(void);
const UIWindowLevel UIWindowLevel_ScreenBlocking(void)
{
    return UIWindowLevelStatusBar + 2.f;
}

#pragma mark -

@implementation OWSWindowRootViewController

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.defaultSupportedOrientations;
}

@end

#pragma mark -

@interface OWSCallWindowRootNavigationViewController : UINavigationController

@end

#pragma mark -

@implementation OWSCallWindowRootNavigationViewController : UINavigationController

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.isIPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

#pragma mark -

@interface OWSWindowManager ()

// UIWindowLevelNormal
@property (nonatomic) UIWindow *rootWindow;

// UIWindowLevel_ReturnToCall
@property (nonatomic) UIWindow *returnToCallWindow;
@property (nonatomic) ReturnToCallViewController *returnToCallViewController;

// UIWindowLevel_CallView
@property (nonatomic) UIWindow *callViewWindow;
@property (nonatomic) UINavigationController *callNavigationController;

// UIWindowLevel_Background if inactive,
// UIWindowLevel_ScreenBlocking() if active.
@property (nonatomic) UIWindow *screenBlockingWindow;

@property (nonatomic) BOOL shouldShowCallView;

@property (nonatomic, nullable) UIViewController<CallViewControllerWindowReference> *callViewController;

@end

#pragma mark -

@implementation OWSWindowManager

- (instancetype)init
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

    [self ensureWindowState];
}

- (UIWindow *)createReturnToCallWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    UIWindow *window = [[OWSWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_ReturnToCall();
    window.opaque = YES;
    window.clipsToBounds = YES;

    ReturnToCallViewController *viewController = [ReturnToCallViewController new];
    self.returnToCallViewController = viewController;

    window.rootViewController = viewController;

    return window;
}

- (UIWindow *)createCallViewWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(rootWindow);

    UIWindow *window = [[OWSWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_CallView();
    window.opaque = YES;
    window.backgroundColor = Theme.launchScreenBackgroundColor;

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = Theme.launchScreenBackgroundColor;

    // NOTE: Do not use OWSNavigationController for call window.
    // It adjusts the size of the navigation bar to reflect the
    // call window.  We don't want those adjustments made within
    // the call window itself.
    OWSCallWindowRootNavigationViewController *navigationController =
        [[OWSCallWindowRootNavigationViewController alloc] initWithRootViewController:viewController];
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
        || window == self.screenBlockingWindow);
}

- (void)updateWindowFrames
{
    OWSAssertIsOnMainThread();

    for (UIWindow *window in @[
             self.rootWindow,
             self.callViewWindow,
             self.screenBlockingWindow,
         ]) {
        if (!CGRectEqualToRect(window.frame, CurrentAppContext().frame)) {
            window.frame = CurrentAppContext().frame;
        }
    }
}

#pragma mark - Calls

- (void)setCallViewController:(nullable UIViewController<CallViewControllerWindowReference> *)callViewController
{
    OWSAssertIsOnMainThread();

    if (callViewController == _callViewController) {
        return;
    }

    _callViewController = callViewController;
}

- (void)startCall:(UIViewController<CallViewControllerWindowReference> *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(callViewController);
    OWSLogInfo(@"startCall");

    self.callViewController = callViewController;

    // Attach callViewController to window.
    [self.callNavigationController popToRootViewControllerAnimated:NO];
    [self.callNavigationController pushViewController:callViewController animated:NO];
    self.shouldShowCallView = YES;

    [self ensureWindowState];
    // This shouldn't be necessary, but in practice we've had at least one user end up with the
    // call view laid out in landscape and then clipped to portrait.
    // An earlier version of this method used UIDevice.ows_setOrientation();
    // we don't want to revert to that because it messes up legitimate orientation detection.
    [UIViewController attemptRotationToDeviceOrientation];
}

- (void)endCall:(UIViewController<CallViewControllerWindowReference> *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(callViewController);
    OWSAssertDebug(self.callViewController);

    if (self.callViewController != callViewController) {
        OWSLogWarn(@"Ignoring end call request from obsolete call view controller.");
        return;
    }

    // Detach callViewController from window.
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

- (void)returnToCallView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.callViewController);

    if (self.shouldShowCallView) {
        [self ensureWindowState];
        return;
    }

    self.shouldShowCallView = YES;

    [self.returnToCallViewController resignCall];
    [self.callViewController returnFromPipWithPipWindow:self.returnToCallWindow];
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
        [self ensureScreenBlockWindowShown];
    } else if (self.callViewController && self.shouldShowCallView) {
        // Show Call View.

        [self ensureRootWindowHidden];
        [self ensureCallViewWindowShown];
        [self ensureReturnToCallWindowHidden];
        [self ensureScreenBlockWindowHidden];
    } else {
        // Show Root Window

        [self ensureRootWindowShown];
        [self ensureScreenBlockWindowHidden];

        if (self.callViewController) {
            // Add "Return to Call" banner

            [self ensureReturnToCallWindowShown];
        } else {
            [self ensureReturnToCallWindowHidden];
        }

        [self ensureCallViewWindowHidden];
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
    if (!self.rootWindow.isKeyWindow || self.rootWindow.hidden) {
        [self.rootWindow makeKeyAndVisible];
    }

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

    OWSLogInfo(@"showing 'return to call' window.");
    self.returnToCallWindow.hidden = NO;
    [self.returnToCallViewController displayForCallViewController:self.callViewController];
}

- (void)ensureReturnToCallWindowHidden
{
    OWSAssertIsOnMainThread();

    if (self.returnToCallWindow.hidden) {
        return;
    }

    OWSLogInfo(@"hiding 'return to call' window.");
    self.returnToCallWindow.hidden = YES;
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
