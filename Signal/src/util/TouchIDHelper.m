//
//  TouchIDHelper.m
//  Signal
//
//  Created by Frederic Barthelemy on 3/4/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <LocalAuthentication/LocalAuthentication.h>

#import "TouchIDHelper.h"

@implementation TouchIDHelper
+ (BOOL)touchIDAvailable {
    LAContext *myContext = [[LAContext alloc] init];
    NSError *authError = nil;
    return [myContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError] && !authError;
}
+ (void)authenticateViaPasswordOrTouchIDCompletion:(void (^)(TSTouchIDAuthResult))completion {
    LAContext *myContext = [[LAContext alloc] init];
    myContext.localizedFallbackTitle = @""; // Disable the "Enter Password" button because this requires extra UI
    if (!self.touchIDAvailable) {
        completion(TSTouchIDAuthResultUnavailable);
    } else {
        [myContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                  localizedReason:NSLocalizedString(@"TOUCHID_SECURITY_PROMPT",@"")
                            reply:^(BOOL success, NSError *error) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    if (error || !success){
                                        DDLogError(@"Error Accessing TouchID: %@",error);
                                        completion(TSTouchIDAuthResultFailed);
                                    } else {
                                        completion(TSTouchIDAuthResultSuccess);
                                    }
                                });
                            }];
    }
}
@end
