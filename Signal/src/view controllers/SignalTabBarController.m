//
//  SignalTabBarController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SignalTabBarController.h"
#import "TSAccountManager.h"

@interface SignalTabBarController ()

@end

@implementation SignalTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (![TSAccountManager isRegistered]){
        [self performSegueWithIdentifier:@"showSignupFlow" sender:self];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
