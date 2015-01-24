//
//  SignalsNavigationController.m
//  Signal
//
//  Created by Dylan Bourgeois on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
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
    [self initializeSocketStatusBar];
    [self initializeObserver];
    [TSSocketManager sendNotification];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)initializeSocketStatusBar
{
    _socketStatusView = [[UIProgressView alloc]initWithProgressViewStyle:UIProgressViewStyleDefault];
    
    CGRect bar = self.navigationBar.frame;
    _socketStatusView.frame = CGRectMake(0, bar.size.height-1.0f, self.view.frame.size.width, 1.0f);
    _socketStatusView.progress = 0.0f;
    [self.navigationBar addSubview:_socketStatusView];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SocketConnectingNotification object:nil];
}

#pragma mark - Socket Status Notifications

-(void)initializeObserver
{
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidOpen)      name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidClose)     name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketIsConnecting) name:SocketConnectingNotification object:nil];
}

-(void)socketDidOpen
{
    [_updateStatusTimer invalidate];
    _socketStatusView.progress = 0.0f;
    _socketStatusView.hidden = YES;
}

-(void)socketDidClose
{
    _socketStatusView.progressTintColor = [UIColor ows_fadedBlueColor];
    if(_socketStatusView.progress >= STALLED_PROGRESS) {
        [ _updateStatusTimer invalidate];
    }
    else {
        _socketStatusView.hidden = NO;
        _updateStatusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateSocketConnecting) userInfo:nil repeats:YES];
    }
}

-(void ) updateSocketConnecting {
    double progress = _socketStatusView.progress + 0.05;
    _socketStatusView.progress = (float)MIN(progress, STALLED_PROGRESS);
}

-(void)socketIsConnecting{
    _socketStatusView.hidden = NO;
    _socketStatusView.progressTintColor = [UIColor ows_fadedBlueColor];
    
}



@end
