//
//  TouchIDManager.h
//  Signal
//
//  Created by Frederic Barthelemy on 3/4/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TouchIDAuthResult) {
    TouchIDAuthResultUserCanceled = -2,
    TouchIDAuthResultUnavailable = -1,
    TouchIDAuthResultFailed = 0,
    TouchIDAuthResultSuccess = 1
};

/**
 * Utility methods for detecting TouchID & using it
 */
@interface TouchIDManager : NSObject
/// Singleton access.
+ (instancetype)shared;
/// Returns true if the app has been backgrounded for under `TouchIDLockTimeoutDefault` seconds.
@property (nonatomic, assign) BOOL isTouchIDUnlocked;
/// Returns `YES` if user recently manually canceled the prompt. Useful for preventing an infinite UI loop of TouchID prompts.
/// Set back to `NO` after backgrounding the app
@property (nonatomic, assign) BOOL userDidCancel;
/// Returns true if the TouchID hardware is present on the device.
- (BOOL)isTouchIDAvailable;
/// Asks user to authenticate with TouchID.
- (void)authenticateViaTouchIDCompletion:(void(^)(TouchIDAuthResult result))completion;

@end
