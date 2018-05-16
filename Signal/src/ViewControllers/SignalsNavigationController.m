//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalsNavigationController.h"
#import "Signal-Swift.h"
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSSocketManager.h>

static double const STALLED_PROGRESS = 0.9;

@interface SignalsNavigationController ()

@property (nonatomic) UIProgressView *socketStatusView;
@property (nonatomic) NSTimer *updateStatusTimer;

@end

#pragma mark -

@implementation SignalsNavigationController

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    //  Attempt 1: negative additionalSafeArea
    // Failure: additionalSafeArea insets cannot be negative
    //    UIEdgeInsets newSafeArea = UIEdgeInsetsMake(-50, 30, 20, 30);
    //    rootViewController.additionalSafeAreaInsets = newSafeArea;

    // Attempt 2: safeAreaInsets on vc.view
    // failure. they're already 0
    //    UIEdgeInsets existingInsets = rootViewController.view.safeAreaInsets;

    // Attempt 3: override topLayoutGuide?
    // Failure - not called.
    // overriding it does no good - it's not called by default layout code.
    // presumably it just existing if you want to use it as an anchor.

    // Attemp 4: sizeForChildContentConainer?
    // Failure - not called.

    // Attempt 5: autoSetDimension on navbar
    // Failure: no effect on rendered size

    // Attempt 6: manually set child frames in will/didLayoutSubviews


    // Attempt 7: Since we can't seem to *shrink* the navbar, maybe we can grow it.
    // make additionalSafeAreaInsets
//    self.additionalSafeAreaInsets = UIEdgeInsetsMake(100, 0, 0, 0);
    
    
    self = [self initWithNavigationBarClass:[SignalNavigationBar class] toolbarClass:nil];
    [self pushViewController:rootViewController animated:NO];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowManagerCallDidChange:)
                                                 name:OWSWindowManagerCallDidChangeNotification
                                               object:nil];

    return self;
}

- (CGSize)sizeForChildContentContainer:(id<UIContentContainer>)container
               withParentContainerSize:(CGSize)parentSize NS_AVAILABLE_IOS(8_0);
{
    CGSize result = [super sizeForChildContentContainer:container withParentContainerSize:parentSize];
    DDLogDebug(@"%@ in %s result: %@", self.logTag, __PRETTY_FUNCTION__, NSStringFromCGSize(result));

    return result;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)windowManagerCallDidChange:(NSNotification *)notification
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    if (OWSWindowManager.sharedManager.hasCall) {

    } else {
    }
}

- (id<UILayoutSupport>)topLayoutGuide
{
    id<UILayoutSupport> result = [super topLayoutGuide];

    DDLogDebug(@"%@ result: %@", self.logTag, result);
    return result;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    //    self.view.safeAreaInsets =
    // Do any additional setup after loading the view.
    [self initializeObserver];
    [self updateSocketStatusView];
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    //    UIEdgeInsets newSafeArea = UIEdgeInsetsMake(50, 10, 20, 30);
    //    // Adjust the safe area insets of the
    //    //  embedded child view controller.
    //    UIViewController *child = self.childViewControllers[0];
    //    child.additionalSafeAreaInsets = newSafeArea;
}

- (void)viewWillLayoutSubviews
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [super viewWillLayoutSubviews];
}

- (void)viewDidLayoutSubviews
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [super viewDidLayoutSubviews];
    //    if (OWSWindowManager.sharedManager.hasCall) {
    //        self.topViewController.view.frame = CGRectMake(0, 44, 375, 583);
    //        self.topViewController.view.bounds = CGRectMake(0, 0, 375, 583);
    //    }
}

- (void)initializeSocketStatusBar {
    if (!_socketStatusView) {
        _socketStatusView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    }

    CGRect bar                          = self.navigationBar.frame;
    _socketStatusView.frame             = CGRectMake(0, bar.size.height - 1.0f, self.view.frame.size.width, 1.0f);
    _socketStatusView.progress          = 0.0f;
    _socketStatusView.progressTintColor = [UIColor ows_fadedBlueColor];

    if (![_socketStatusView superview]) {
        [self.navigationBar addSubview:_socketStatusView];
    }
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Socket Status Notifications

- (void)initializeObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketManagerStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(isCensorshipCircumventionActiveDidChange:)
                                                 name:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                                               object:nil];
}

- (void)isCensorshipCircumventionActiveDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateSocketStatusView];
}

- (void)socketManagerStateDidChange {
    OWSAssertIsOnMainThread();

    [self updateSocketStatusView];
}

- (void)updateSocketStatusView {
    OWSAssertIsOnMainThread();

    if ([OWSSignalService sharedInstance].isCensorshipCircumventionActive) {
        [_updateStatusTimer invalidate];
        [_socketStatusView removeFromSuperview];
        _socketStatusView = nil;
        return;
    }

    switch ([TSSocketManager sharedManager].state) {
        case SocketManagerStateClosed:
            if (_socketStatusView == nil) {
                [self initializeSocketStatusBar];
                [_updateStatusTimer invalidate];
                _updateStatusTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.5
                                                                          target:self
                                                                        selector:@selector(updateProgress)
                                                                        userInfo:nil
                                                                         repeats:YES];

            } else if (_socketStatusView.progress >= STALLED_PROGRESS) {
                [_updateStatusTimer invalidate];
            }
            break;
        case SocketManagerStateConnecting:
            // Do nothing.
            break;
        case SocketManagerStateOpen:
            [_updateStatusTimer invalidate];
            [_socketStatusView removeFromSuperview];
            _socketStatusView = nil;
            break;
    }
}

- (void)updateProgress {
    double progress = _socketStatusView.progress + 0.05;
    _socketStatusView.progress = (float) MIN(progress, STALLED_PROGRESS);
}

@end
