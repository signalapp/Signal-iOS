//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SignalsViewController.h"

extern NSString *const AppDelegateStoryboardMain;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) SignalsViewController *signalVC;

@end
