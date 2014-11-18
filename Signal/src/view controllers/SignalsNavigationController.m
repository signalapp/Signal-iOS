//
//  SignalsNavigationController.m
//  Signal
//
//  Created by Dylan Bourgeois on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SignalsNavigationController.h"

@interface SignalsNavigationController ()

@end

@implementation SignalsNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self initializeSocketStatusBar];
    
    _socket = [[Socket alloc]init];
    
    [self initializeObserver];
    
    _socket.status = kSocketStatusOpen;
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
    _socketStatusView.progressTintColor = [UIColor greenColor];
    _socketStatusView.progress = 1.0f;
    [self.navigationBar addSubview:_socketStatusView];
}

#pragma mark - Socket Status Notifications

-(void)initializeObserver
{
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidOpen) name:SocketOpenedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketDidClose) name:SocketClosedNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(socketIsConnecting) name:SocketConnectingNotification object:nil];
}

-(void)socketDidOpen
{
    _socketStatusView.progressTintColor = [UIColor greenColor];
}

-(void)socketDidClose
{
    _socketStatusView.progressTintColor = [UIColor redColor];
    
}

-(void)socketIsConnecting
{
    _socketStatusView.progressTintColor = [UIColor yellowColor];
    
}



@end
