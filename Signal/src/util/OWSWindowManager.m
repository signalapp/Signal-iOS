//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSWindowManager.h"
#import "Signal-Swift.h"
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const UIWindowLevel UIWindowLevel_Background = -1.f;
const UIWindowLevel UIWindowLevel_ReturnToCall(void);
const UIWindowLevel UIWindowLevel_ReturnToCall(void)
{
    return UIWindowLevelNormal + 1.f;
}
const UIWindowLevel UIWindowLevel_CallView(void);
const UIWindowLevel UIWindowLevel_CallView(void)
{
    return UIWindowLevelNormal + 2.f;
}
const UIWindowLevel UIWindowLevel_ScreenBlocking(void);
const UIWindowLevel UIWindowLevel_ScreenBlocking(void)
{
    return UIWindowLevelStatusBar + 1.f;
}

const int kReturnToCallWindowHeight = 40.f;

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

// UIWindowLevel_CallView
@property (nonatomic) UIWindow *callViewWindow;

// UIWindowLevel_Background if inactive,
// UIWindowLevel_ScreenBlocking() if active.
@property (nonatomic) UIWindow *screenBlockingWindow;

@property (nonatomic) BOOL isScreenBlockActive;

@property (nonatomic) BOOL isCallViewActive;

@property (nonatomic, nullable) UIViewController *callViewController;

@property (nonatomic, nullable) UIResponder *rootWindowResponder;
@property (nonatomic, nullable, weak) UIViewController *rootFrontmostViewController;

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

    self.returnToCallWindow = [OWSWindowManager createReturnToCallWindow:rootWindow];
    self.callViewWindow = [OWSWindowManager createCallViewWindow:rootWindow];

    [self ensureWindowState];
}

+ (UIWindow *)createReturnToCallWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    // "Return to call" should remain at the top of the screen.
    //
    // TODO: Extend below the status bar.
    CGRect windowFrame = rootWindow.bounds;
    windowFrame.size.height = kReturnToCallWindowHeight;
    UIWindow *window = [[UIWindow alloc] initWithFrame:windowFrame];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_ReturnToCall();
    window.opaque = YES;
    // TODO:
    window.backgroundColor = UIColor.ows_materialBlueColor;
    window.backgroundColor = [UIColor redColor];

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = UIColor.ows_materialBlueColor;
    viewController.view.backgroundColor = [UIColor redColor];

    UIView *rootView = viewController.view;
    rootView.userInteractionEnabled = YES;
    [rootView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(returnToCallWasTapped:)]];

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(@"CALL_WINDOW_RETURN_TO_CALL", @"Label for the 'return to call' indicator.");
    label.textColor = [UIColor whiteColor];
    // TODO: Dynamic type?
    label.font = [UIFont ows_mediumFontWithSize:18.f];
    [rootView addSubview:label];
    [label autoCenterInSuperview];

    window.rootViewController = viewController;

    return window;
}

+ (UIWindow *)createCallViewWindow:(UIWindow *)rootWindow
{
    OWSAssertIsOnMainThread();
    OWSAssert(rootWindow);

    UIWindow *window = [[UIWindow alloc] initWithFrame:rootWindow.bounds];
    window.hidden = YES;
    window.windowLevel = UIWindowLevel_CallView();
    window.opaque = YES;
    window.backgroundColor = [UIColor ows_materialBlueColor];

    UIViewController *viewController = [OWSWindowRootViewController new];
    viewController.view.backgroundColor = [UIColor ows_materialBlueColor];

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;

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
    // Attach callViewController from window.
    OWSAssert([self.callViewWindow.rootViewController isKindOfClass:[UINavigationController class]]);
    UINavigationController *navigationController = (UINavigationController *)self.callViewWindow.rootViewController;
    [navigationController pushViewController:callViewController animated:NO];
    self.isCallViewActive = YES;

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
    OWSAssert([self.callViewWindow.rootViewController isKindOfClass:[UINavigationController class]]);
    UINavigationController *navigationController = (UINavigationController *)self.callViewWindow.rootViewController;
    [navigationController popToRootViewControllerAnimated:NO];
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

    if (self.isScreenBlockActive) {
        // Show Screen Block.

        [self hideRootWindowIfNecessary];
        [self hideReturnToCallWindowIfNecessary];
        [self hideCallViewWindowIfNecessary];
        [self showScreenBlockWindowIfNecessary];
    } else if (self.callViewController && self.isCallViewActive) {
        // Show Call View.

        [self hideRootWindowIfNecessary];
        [self hideReturnToCallWindowIfNecessary];
        [self showCallViewWindowIfNecessary];
        [self hideScreenBlockWindowIfNecessary];
    } else if (self.callViewController) {
        // Show Root Window + "Return to Call".

        [self showRootWindowIfNecessary];
        [self showReturnToCallWindowIfNecessary];
        [self hideCallViewWindowIfNecessary];
        [self hideScreenBlockWindowIfNecessary];
    } else {
        // Show Root Window

        [self showRootWindowIfNecessary];
        [self hideReturnToCallWindowIfNecessary];
        [self hideCallViewWindowIfNecessary];
        [self hideScreenBlockWindowIfNecessary];
    }

    DDLogVerbose(@"%@ rootWindow: %d %f", self.logTag, self.rootWindow.hidden, self.rootWindow.windowLevel);
    DDLogVerbose(@"%@ returnToCallWindow: %d %f",
        self.logTag,
        self.returnToCallWindow.hidden,
        self.returnToCallWindow.windowLevel);
    DDLogVerbose(@"%@ callViewWindow: %d %f", self.logTag, self.callViewWindow.hidden, self.callViewWindow.windowLevel);
    DDLogVerbose(@"%@ screenBlockingWindow: %d %f",
        self.logTag,
        self.screenBlockingWindow.hidden,
        self.screenBlockingWindow.windowLevel);

    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"%@ ...rootWindow: %d %f", self.logTag, self.rootWindow.hidden, self.rootWindow.windowLevel);
        DDLogVerbose(@"%@ ...returnToCallWindow: %d %f",
            self.logTag,
            self.returnToCallWindow.hidden,
            self.returnToCallWindow.windowLevel);
        DDLogVerbose(
            @"%@ ...callViewWindow: %d %f", self.logTag, self.callViewWindow.hidden, self.callViewWindow.windowLevel);
        DDLogVerbose(@"%@ ...screenBlockingWindow: %d %f",
            self.logTag,
            self.screenBlockingWindow.hidden,
            self.screenBlockingWindow.windowLevel);
    });
}

- (void)showRootWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.rootWindow.hidden) {
        DDLogInfo(@"%@ showing root window.", self.logTag);
    }

    BOOL shouldTryToRestoreFirstResponder = self.rootWindow.hidden;

    [self.rootWindow makeKeyAndVisible];

    // When we hide the block window, try to restore the first
    // responder of the root window.
    //
    // It's important we restore first responder status once the user completes
    // In some cases, (RegistrationLock Reminder) it just puts the keyboard back where
    // the user needs it, saving them a tap.
    // But in the case of an inputAccessoryView, like the ConversationViewController,
    // failing to restore firstResponder could hide the input toolbar.
    if (shouldTryToRestoreFirstResponder) {
        UIViewController *rootFrontmostViewController =
            [UIApplication.sharedApplication frontmostViewControllerIgnoringAlerts];

        DDLogInfo(@"%@ trying to restore self.rootWindowResponder: %@ (%@ ? %@ == %d)",
            self.logTag,
            self.rootWindowResponder,
            [self.rootFrontmostViewController class],
            rootFrontmostViewController,
            self.rootFrontmostViewController == rootFrontmostViewController);
        if (self.rootFrontmostViewController == rootFrontmostViewController) {
            [self.rootWindowResponder becomeFirstResponder];
        } else {
            [rootFrontmostViewController becomeFirstResponder];
        }
    }

    self.rootWindowResponder = nil;
    self.rootFrontmostViewController = nil;
}

- (void)hideRootWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (!self.rootWindow.hidden) {
        DDLogInfo(@"%@ hiding root window.", self.logTag);
    }

    // When we hide the root window, try to capture its first responder and
    // current vc before it is hidden.
    if (!self.rootWindow.hidden) {
        self.rootWindowResponder = [UIResponder currentFirstResponder];
        self.rootFrontmostViewController = [UIApplication.sharedApplication frontmostViewControllerIgnoringAlerts];
        DDLogInfo(@"%@ trying to capture self.rootWindowResponder: %@ (%@)",
            self.logTag,
            self.rootWindowResponder,
            [self.rootFrontmostViewController class]);
    }

    self.rootWindow.hidden = YES;
}

- (void)showReturnToCallWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.returnToCallWindow.hidden) {
        DDLogInfo(@"%@ showing 'return to call' window.", self.logTag);
    }

    self.returnToCallWindow.hidden = NO;
}

- (void)hideReturnToCallWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (!self.returnToCallWindow.hidden) {
        DDLogInfo(@"%@ hiding 'return to call' window.", self.logTag);
    }

    self.returnToCallWindow.hidden = YES;
}

- (void)showCallViewWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.callViewWindow.hidden) {
        DDLogInfo(@"%@ showing call window.", self.logTag);
    }

    [self.callViewWindow makeKeyAndVisible];
    [self.callViewWindow.rootViewController becomeFirstResponder];
}

- (void)hideCallViewWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (!self.callViewWindow.hidden) {
        DDLogInfo(@"%@ hiding call window.", self.logTag);
    }

    self.callViewWindow.hidden = YES;
}

- (void)showScreenBlockWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_ScreenBlocking()) {
        DDLogInfo(@"%@ showing block window.", self.logTag);
    }

    self.screenBlockingWindow.windowLevel = UIWindowLevel_ScreenBlocking();
    [self.screenBlockingWindow.rootViewController becomeFirstResponder];
}

- (void)hideScreenBlockWindowIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.screenBlockingWindow.windowLevel != UIWindowLevel_Background) {
        DDLogInfo(@"%@ hiding block window.", self.logTag);
    }

    // Never hide the blocking window (that can lead to bad frames).
    // Instead, manipulate its window level to move it in front of
    // or behind the root window.
    self.screenBlockingWindow.windowLevel = UIWindowLevel_Background;
    [self.screenBlockingWindow resignFirstResponder];
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
