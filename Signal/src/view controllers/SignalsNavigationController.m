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

@implementation SignalsNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self initializeObserver];
    [TSSocketManager sendNotification];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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


@end
