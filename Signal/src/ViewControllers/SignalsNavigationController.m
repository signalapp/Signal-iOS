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
    self = [self initWithNavigationBarClass:[SignalNavigationBar class] toolbarClass:nil];
    [self pushViewController:rootViewController animated:NO];
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self initializeObserver];
    [self updateSocketStatusView];
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
