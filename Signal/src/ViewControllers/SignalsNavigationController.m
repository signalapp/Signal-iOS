//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalsNavigationController.h"

#import "UIUtil.h"

@interface SignalsNavigationController ()

@end

static double const STALLED_PROGRESS = 0.9;
@implementation SignalsNavigationController


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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Socket Status Notifications

- (void)initializeObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketManagerStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
}

- (void)socketManagerStateDidChange {
    OWSAssert([NSThread isMainThread]);
    
    [self updateSocketStatusView];
}

- (void)updateSocketStatusView {
    OWSAssert([NSThread isMainThread]);
    
    switch ([TSSocketManager sharedManager].state) {
        case SocketManagerStateClosed:
            if (_socketStatusView == nil) {
                [self initializeSocketStatusBar];
                _updateStatusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
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
            for (UIView *view in self.navigationBar.subviews) {
                if ([view isKindOfClass:[UIProgressView class]]) {
                    [view removeFromSuperview];
                    _socketStatusView = nil;
                }
            }
            break;
    }
}

- (void)updateProgress {
    double progress = _socketStatusView.progress + 0.05;
    _socketStatusView.progress = (float) MIN(progress, STALLED_PROGRESS);
}

@end
