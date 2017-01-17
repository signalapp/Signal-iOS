//
//  TouchIDManager.m
//  Signal
//
//  Created by Frederic Barthelemy on 3/4/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <LocalAuthentication/LocalAuthentication.h>
#import "TouchIDManager.h"

/// The number of seconds the app must be backgrounded before we lock the screen.
NSTimeInterval const TouchIDLockTimeoutDefault = 60;

@interface TouchIDManager()
/// The time (since epoch) the phone was backgrounded during an unlocked state. Will be 0 if never unlocked.
@property (nonatomic, assign) NSTimeInterval timeBackgroundedAfterUnlock;
@end

@implementation TouchIDManager

+ (instancetype)shared {
    static TouchIDManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[TouchIDManager alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:sharedInstance selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    });
    return sharedInstance;
}

- (void)applicationDidEnterBackground:(NSNotification *)note {
    // We want to reset `timeBackgroundedAfterUnlock` when the user backgrounds the app.
    // Note that this notification does not get called during the TouchID presentation, unlike
    // the AppDelegate's `applicationWillResignActive`.
    if (!self.userDidCancel) {
        // Only want to reset timeout if the app is backgrounded and the user _hasn't_ recently canceled the TouchID prompt.
        self.timeBackgroundedAfterUnlock = [NSDate date].timeIntervalSince1970;
    }
    self.userDidCancel = NO;
}

- (BOOL)isTouchIDAvailable {
    LAContext *myContext = [[LAContext alloc] init];
    NSError *authError = nil;
    return [myContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError] && !authError;
}

- (void)authenticateViaTouchIDCompletion:(void (^)(TouchIDAuthResult))completion {
    LAContext *myContext = [[LAContext alloc] init];
    // Disable the "Enter Password" button because we don't currently have a password fallback
    // See http://stackoverflow.com/a/29498981
    myContext.localizedFallbackTitle = @""; 
    if (!self.isTouchIDAvailable) {
        completion(TouchIDAuthResultUnavailable);
    } else {
        [myContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                  localizedReason:NSLocalizedString(@"TOUCHID_SECURITY_PROMPT",@"")
                            reply:^(BOOL success, NSError *error) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    if (error || !success){
                                        DDLogError(@"Error Accessing TouchID: %@",error);
                                        if (error.code == -2) {
                                            // User canceled
                                            self.userDidCancel = YES;
                                            completion(TouchIDAuthResultUserCanceled);
                                        } else {
                                            completion(TouchIDAuthResultFailed);
                                        }
                                    } else {
                                        self.timeBackgroundedAfterUnlock = [NSDate date].timeIntervalSince1970;
                                        completion(TouchIDAuthResultSuccess);
                                    }
                                });
                            }];
    }
}

- (BOOL)isTouchIDUnlocked {
    NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
    return currentTime - self.timeBackgroundedAfterUnlock <= TouchIDLockTimeoutDefault;
}

@end
