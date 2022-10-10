//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const IsScreenBlockActiveDidChangeNotification = @"IsScreenBlockActiveDidChangeNotification";

// Behind everything, especially the root window.
const UIWindowLevel UIWindowLevel_Background = -1.f;

// In front of the status bar and CallView
const UIWindowLevel UIWindowLevel_ScreenBlocking(void);
const UIWindowLevel UIWindowLevel_ScreenBlocking(void)
{
    return UIWindowLevelStatusBar + 2.f;
}

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

// UIWindowLevel_Background if inactive,
// UIWindowLevel_ScreenBlocking() if active.
@property (nonatomic) UIWindow *screenBlockingWindow;

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
    return (window == self.rootWindow || window == self.screenBlockingWindow);
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
        [self ensureScreenBlockWindowShown];
    }
    else {
        // Show Root Window

        [self ensureRootWindowShown];
        [self ensureScreenBlockWindowHidden];
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
