//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSWindowManagerCallDidChangeNotification = @"OWSWindowManagerCallDidChangeNotification";

NSString *const IsScreenBlockActiveDidChangeNotification = @"IsScreenBlockActiveDidChangeNotification";

const CGFloat OWSWindowManagerCallBannerHeight(void)
{
    return CurrentAppContext().statusBarHeight + 20;
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

@interface OWSWindowManager ()

// UIWindowLevelNormal
@property (nonatomic) UIWindow *rootWindow;

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
    return SMKEnvironment.shared.windowManager;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    return self;
}

- (void)setupWithRootWindow:(UIWindow *)rootWindow screenBlockingWindow:(UIWindow *)screenBlockingWindow
{
    self.rootWindow = rootWindow;
    self.screenBlockingWindow = screenBlockingWindow;

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
    
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self hideMenuActionsWindow];
}

- (UIWindow *)createMenuActionsWindowWithRoowWindow:(UIWindow *)rootWindow
{
    UIWindow *window = [[MessageActionsWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.backgroundColor = UIColor.clearColor;

    return window;
}

- (UIWindow *)createCallViewWindow:(UIWindow *)rootWindow
{
    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_CallView();
    window.opaque = YES;
    // TODO: What's the right color to use here?
    window.backgroundColor = [UIColor blackColor];

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = [UIColor blackColor];

    // NOTE: Do not use OWSNavigationController for call window.
    // It adjusts the size of the navigation bar to reflect the
    // call window.  We don't want those adjustments made within
    // the call window itself.
    OWSWindowRootNavigationViewController *navigationController =
        [[OWSWindowRootNavigationViewController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;
    self.callNavigationController = navigationController;

    window.rootViewController = navigationController;

    return window;
}

- (void)setIsScreenBlockActive:(BOOL)isScreenBlockActive
{
    _isScreenBlockActive = isScreenBlockActive;

    [self ensureWindowState];

    [[NSNotificationCenter defaultCenter] postNotificationName:IsScreenBlockActiveDidChangeNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (BOOL)isAppWindow:(UIWindow *)window
{
    return (window == self.rootWindow || window == self.callViewWindow
        || window == self.menuActionsWindow || window == self.screenBlockingWindow);
}

#pragma mark - Message Actions

- (BOOL)isPresentingMenuActions
{
    return self.menuActionsViewController != nil;
}

- (void)showMenuActionsWindow:(UIViewController *)menuActionsViewController
{
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
    if (callViewController == _callViewController) {
        return;
    }

    _callViewController = callViewController;

    [NSNotificationCenter.defaultCenter postNotificationName:OWSWindowManagerCallDidChangeNotification object:nil];
}

- (void)startCall:(UIViewController *)callViewController
{
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
    if (self.callViewController != callViewController) {
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
    self.shouldShowCallView = NO;

    [self ensureWindowState];
}

- (void)showCallView
{
    self.shouldShowCallView = YES;

    [self ensureWindowState];
}

- (BOOL)hasCall
{
    return self.callViewController != nil;
}

#pragma mark - Window State

- (void)ensureWindowState
{
    // To avoid bad frames, we never want to hide the blocking window, so we manipulate
    // its window level to "hide" it behind other windows.  The other windows have fixed
    // window level and are shown/hidden as necessary.
    //
    // Note that we always "hide" before we "show".
    if (self.isScreenBlockActive) {
        // Show Screen Block.

        [self ensureRootWindowHidden];
        [self ensureCallViewWindowHidden];
        [self ensureMessageActionsWindowHidden];
        [self ensureScreenBlockWindowShown];
    } else if (self.callViewController && self.shouldShowCallView) {
        // Show Call View.

        [self ensureRootWindowHidden];
        [self ensureCallViewWindowShown];
        [self ensureMessageActionsWindowHidden];
        [self ensureScreenBlockWindowHidden];
    } else {
        // Show Root Window

        [self ensureRootWindowShown];
        [self ensureCallViewWindowHidden];
        [self ensureScreenBlockWindowHidden];

        if (self.menuActionsViewController) {
            // Add "Message Actions" action sheet

            [self ensureMessageActionsWindowShown];
        } else {
            [self ensureMessageActionsWindowHidden];
        }
    }
}

- (void)ensureRootWindowShown
{
    // By calling makeKeyAndVisible we ensure the rootViewController becomes first responder.
    // In the normal case, that means the SignalViewController will call `becomeFirstResponder`
    // on the vc on top of its navigation stack.
    [self.rootWindow makeKeyAndVisible];

    [self fixit_workAroundRotationIssue];
}

- (void)ensureRootWindowHidden
{
    self.rootWindow.hidden = YES;
}

- (void)ensureCallViewWindowShown
{
    [self.callViewWindow makeKeyAndVisible];
}

- (void)ensureCallViewWindowHidden
{
    self.callViewWindow.hidden = YES;
}

- (void)ensureMessageActionsWindowShown
{
    // Do not make key, we want the keyboard to stay popped.
    self.menuActionsWindow.hidden = NO;
}

- (void)ensureMessageActionsWindowHidden
{
    self.menuActionsWindow.hidden = YES;
}

- (void)ensureScreenBlockWindowShown
{
    self.screenBlockingWindow.windowLevel = UIWindowLevel_ScreenBlocking();
    [self.screenBlockingWindow makeKeyAndVisible];
}

- (void)ensureScreenBlockWindowHidden
{
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
        return;
    }
    SEL selector1 = NSSelectorFromString(selectorString1);

    if (![self.rootWindow respondsToSelector:selector1]) {
        return;
    }
    IMP imp1 = [self.rootWindow methodForSelector:selector1];
    BOOL (*func1)(id, SEL) = (void *)imp1;
    BOOL isDisabled = func1(self.rootWindow, selector1);

    if (isDisabled) {
        // The remainder of this method calls:
        //   [[UIScrollToDismissSupport supportForScreen:UIScreen.main] finishScrollViewTransition]
        // after verifying the methods/classes exist.

        // NSString *encodedKlassString = @"UIScrollToDismissSupport".encodedForSelector;
        NSString *encodedKlassString = @"ZlpkdAQBfX1lAVV6BX56BQVkBwICAQQG";
        NSString *_Nullable klassString = encodedKlassString.decodedForSelector;
        if (klassString == nil) {
            return;
        }
        id klass = NSClassFromString(klassString);
        if (klass == nil) {
            return;
        }

        // NSString *encodedSelector2String = @"supportForScreen:".encodedForSelector;
        NSString *encodedSelector2String = @"BQcCAgEEBlcBBGR0BHZ2AEs=";
        NSString *_Nullable selector2String = encodedSelector2String.decodedForSelector;
        if (selector2String == nil) {
            return;
        }
        SEL selector2 = NSSelectorFromString(selector2String);
        if (![klass respondsToSelector:selector2]) {
            return;
        }
        IMP imp2 = [klass methodForSelector:selector2];
        id (*func2)(id, SEL, UIScreen *) = (void *)imp2;
        id dismissSupport = func2(klass, selector2, UIScreen.mainScreen);

        // NSString *encodedSelector3String = @"finishScrollViewTransition".encodedForSelector;
        NSString *encodedSelector3String = @"d3oAegV5ZHQEAX19Z3p2CWUEcgAFegZ6AQA=";
        NSString *_Nullable selector3String = encodedSelector3String.decodedForSelector;
        if (selector3String == nil) {
            return;
        }
        SEL selector3 = NSSelectorFromString(selector3String);
        if (![dismissSupport respondsToSelector:selector3]) {
            return;
        }
        IMP imp3 = [dismissSupport methodForSelector:selector3];
        void (*func3)(id, SEL) = (void *)imp3;
        func3(dismissSupport, selector3);
    }
}

@end

NS_ASSUME_NONNULL_END
