//
//  SignalsNavigationController.h
//  Signal
//
//  Created by Dylan Bourgeois on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "APNavigationController.h"
#import "TSSocketManager.h"
@interface SignalsNavigationController : APNavigationController
@property (nonatomic, strong) UIProgressView *socketStatusView;
@property (nonatomic, strong) NSTimer *updateStatusTimer;
@end
