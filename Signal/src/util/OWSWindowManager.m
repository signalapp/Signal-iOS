//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import "Signal-Swift.h"
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

// Behind everything, especially the root window.
const UIWindowLevel UIWindowLevel_Background = -1.f;

// MJK FIXME: this *looks* right, but then we can't receive taps that
// touch the status bar. We could: obscure status bar, but that looks wrong.
// have *another* transparent window?
//
// In front of the root window, behind the status bar
// but behind the screen blocking window.
const UIWindowLevel UIWindowLevel_ReturnToCall(void);
const UIWindowLevel UIWindowLevel_ReturnToCall(void)
{
    return UIWindowLevelStatusBar - 1.f;
}

// In front of the root window, behind the screen blocking window.
const UIWindowLevel UIWindowLevel_CallView(void);
const UIWindowLevel UIWindowLevel_CallView(void)
{
    return UIWindowLevelNormal + 1.f;
}

// In front of everything, including the status bar.
const UIWindowLevel UIWindowLevel_ScreenBlocking(void);
const UIWindowLevel UIWindowLevel_ScreenBlocking(void)
{
    return UIWindowLevelStatusBar + 2.f;
}

@implementation OWSWindowRootViewController

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

@end

#pragma mark -

@interface OWSWindowManager ()

// UIWindowLevelNormal
@property (nonatomic) UIWindow *rootWindow;

// UIWindowLevel_ReturnToCall
@property (nonatomic) UIWindow *returnToCallWindow;
@property (nonatomic) UILabel *returnToCallLabel;

// UIWindowLevel_CallView
@property (nonatomic) UIWindow *callViewWindow;
@property (nonatomic) UINavigationController *callNavigationController;

// UIWindowLevel_Background if inactive,
// UIWindowLevel_ScreenBlocking() if active.
@property (nonatomic) UIWindow *screenBlockingWindow;

@property (nonatomic) BOOL isScreenBlockActive;

@property (nonatomic) BOOL isCallViewActive;

@property (nonatomic, nullable) UIViewController *callViewController;

@end

#pragma mark -

@implementation OWSWindowManager

+ (instancetype)sharedManager
{
    static OWSWindowManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
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
    OWSAssert(rootWindow);
    OWSAssert(!self.rootWindow);
    OWSAssert(screenBlockingWindow);
    OWSAssert(!self.screenBlockingWindow);

    self.rootWindow = rootWindow;
    self.screenBlockingWindow = screenBlockingWindow;

    self.returnToCallWindow = [self createReturnToCallWindow:rootWindow];
    self.callViewWindow = [self createCallViewWindow:rootWindow];

    [self updateReturnToCallWindowLayout];

    [self ensureWindowState];
}

- (UIWindow *)createReturnToCallWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    // "Return to call" should remain at the top of the screen.
    CGRect windowFrame = rootWindow.bounds;
    // Use zero height until updateReturnToCallWindowLayout.
    windowFrame.size.height = 0;
    UIWindow *window = [[UIWindow alloc] initWithFrame:windowFrame];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_ReturnToCall();
    window.opaque = YES;
    // This is the color of the iOS "return to call" banner.
    // TODO: What's the right color to use here?
    UIColor *backgroundColor = [UIColor colorWithRGBHex:0x4cd964];
    window.backgroundColor = backgroundColor;

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = backgroundColor;

    UIView *rootView = viewController.view;
    rootView.userInteractionEnabled = YES;
    [rootView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(returnToCallWasTapped:)]];
    rootView.layoutMargins = UIEdgeInsetsZero;

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(@"CALL_WINDOW_RETURN_TO_CALL", @"Label for the 'return to call' banner.");
    label.textColor = [UIColor whiteColor];
    // System UI doesn't use dynamic type; neither do we.
    label.font = [UIFont ows_regularFontWithSize:14.f];
    [rootView addSubview:label];

    // returnToCallLabel uses manual layout.
    //
    // TODO: Is there a better way to do this?
    label.translatesAutoresizingMaskIntoConstraints = NO;
    self.returnToCallLabel = label;

    window.rootViewController = viewController;

    return window;
}

- (void)updateReturnToCallWindowLayout
{
    OWSAssertIsOnMainThread();

    CGRect statusBarFrame = UIApplication.sharedApplication.statusBarFrame;
    CGFloat statusBarHeight = statusBarFrame.size.height;

    CGRect windowFrame = self.rootWindow.bounds;
    windowFrame.size.height = statusBarHeight + 20.f;
    self.returnToCallWindow.frame = windowFrame;
    self.returnToCallWindow.rootViewController.view.frame = windowFrame;

    [self.returnToCallLabel sizeToFit];
    CGRect labelFrame = self.returnToCallLabel.frame;
    labelFrame.origin.x = floor(windowFrame.size.width - labelFrame.size.width);
    self.returnToCallLabel.frame = labelFrame;

    UIView *rootView = self.returnToCallWindow.rootViewController.view;

    [rootView setNeedsLayout];
    [rootView layoutIfNeeded];

    for (UIView *subview in rootView.subviews) {
        [subview setNeedsLayout];
        [subview layoutIfNeeded];
    }
}

- (UIWindow *)createCallViewWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_CallView();
    window.opaque = YES;
    // TODO: What's the right color to use here?
    window.backgroundColor = [UIColor ows_materialBlueColor];

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = [UIColor ows_materialBlueColor];

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;
    OWSAssert(!self.callNavigationController);
    self.callNavigationController = navigationController;

    window.rootViewController = navigationController;

    return window;
}

- (void)setIsScreenBlockActive:(BOOL)isScreenBlockActive
{
    OWSAssertIsOnMainThread();

    _isScreenBlockActive = isScreenBlockActive;

    [self ensureWindowState];
}

#pragma mark - Calls

- (void)startCall:(UIViewController *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssert(callViewController);
    OWSAssert(!self.callViewController);

    self.callViewController = callViewController;
    // Attach callViewController to window.
    [self.callNavigationController popToRootViewControllerAnimated:NO];
    [self.callNavigationController pushViewController:callViewController animated:NO];
    self.isCallViewActive = YES;

    [self updateReturnToCallWindowLayout];

    [self ensureWindowState];
}

- (void)endCall:(UIViewController *)callViewController
{
    OWSAssertIsOnMainThread();
    OWSAssert(callViewController);
    OWSAssert(self.callViewController);

    if (self.callViewController != callViewController) {
        DDLogWarn(@"%@ Ignoring end call request from obsolete call view controller.", self.logTag);
        return;
    }

    // Dettach callViewController from window.
    [self.callNavigationController popToRootViewControllerAnimated:NO];
    self.callViewController = nil;
    self.isCallViewActive = NO;

    [self ensureWindowState];
}

- (void)leaveCallView
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.callViewController);
    OWSAssert(self.isCallViewActive);

    self.isCallViewActive = NO;

    [self ensureWindowState];
}

- (void)returnToCallView
{
    OWSAssertIsOnMainThread();
    OWSAssert(self.callViewController);
    OWSAssert(!self.isCallViewActive);

    self.isCallViewActive = YES;

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
    OWSAssert(self.rootWindow);
    OWSAssert(self.returnToCallWindow);
    OWSAssert(self.callViewWindow);
    OWSAssert(self.screenBlockingWindow);

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
    } else if (self.callViewController && self.isCallViewActive) {
        // Show Call View.

        [self ensureRootWindowHidden];
        [self ensureReturnToCallWindowHidden];
        [self ensureCallViewWindowShown];
        [self ensureScreenBlockWindowHidden];
    } else if (self.callViewController) {
        // Show Root Window + "Return to Call".

        [self ensureRootWindowShown];
        [self ensureReturnToCallWindowShown];
        [self ensureCallViewWindowHidden];
        [self ensureScreenBlockWindowHidden];
    } else {
        // Show Root Window

        [self ensureRootWindowShown];
        [self ensureReturnToCallWindowHidden];
        [self ensureCallViewWindowHidden];
        [self ensureScreenBlockWindowHidden];
    }
}

- (void)ensureRootWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.rootWindow.hidden) {
        DDLogInfo(@"%@ showing root window.", self.logTag);
    }

    // By calling makeKeyAndVisible we ensure the rootViewController becomes firt responder.
    // In the normal case, that means the SignalViewController will call `becomeFirstResponder`
    // on the vc on top of its navigation stack.
    [self.rootWindow makeKeyAndVisible];

}

- (void)ensureRootWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.rootWindow.hidden) {
        DDLogInfo(@"%@ hiding root window.", self.logTag);
    }

    self.rootWindow.hidden = YES;
}

- (void)ensureReturnToCallWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.returnToCallWindow.hidden) {
        DDLogInfo(@"%@ showing 'return to call' window.", self.logTag);

        [self.returnToCallLabel.layer removeAllAnimations];
        self.returnToCallLabel.alpha = 1.f;
        [UIView animateWithDuration:1.f
            delay:0.f
            options:(UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                        | UIViewAnimationOptionBeginFromCurrentState)
            animations:^{
                self.returnToCallLabel.alpha = 0.f;
            }
            completion:^(BOOL finished) {
                self.returnToCallLabel.alpha = 1.f;
            }];
    }

    self.returnToCallWindow.hidden = NO;

    [self updateReturnToCallWindowLayout];
}

- (void)ensureReturnToCallWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.returnToCallWindow.hidden) {
        DDLogInfo(@"%@ hiding 'return to call' window.", self.logTag);
    }

    self.returnToCallWindow.hidden = YES;
    [self.returnToCallLabel.layer removeAllAnimations];
}

- (void)ensureCallViewWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.callViewWindow.hidden) {
        DDLogInfo(@"%@ showing call window.", self.logTag);
    }

    [self.callViewWindow makeKeyAndVisible];
}

- (void)ensureCallViewWindowHidden
{
    OWSAssertIsOnMainThread();

    if (!self.callViewWindow.hidden) {
        DDLogInfo(@"%@ hiding call window.", self.logTag);
    }

    self.callViewWindow.hidden = YES;
}

- (void)ensureScreenBlockWindowShown
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_ScreenBlocking()) {
        DDLogInfo(@"%@ showing block window.", self.logTag);
    }

    self.screenBlockingWindow.windowLevel = UIWindowLevel_ScreenBlocking();
    [self.screenBlockingWindow makeKeyAndVisible];
}

- (void)ensureScreenBlockWindowHidden
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_Background) {
        DDLogInfo(@"%@ hiding block window.", self.logTag);
    }

    // Never hide the blocking window (that can lead to bad frames).
    // Instead, manipulate its window level to move it in front of
    // or behind the root window.
    self.screenBlockingWindow.windowLevel = UIWindowLevel_Background;
}

#pragma mark - Events

- (void)returnToCallWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    [self returnToCallView];
}

@end

NS_ASSUME_NONNULL_END
