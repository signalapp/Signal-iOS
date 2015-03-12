//
//  TouchIDHelper.h
//  Signal
//
//  Created by Frederic Barthelemy on 3/4/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TSTouchIDAuthResult) {
    TSTouchIDAuthResultUnavailable = -1,
    TSTouchIDAuthResultFailed = 0,
    TSTouchIDAuthResultSuccess = 1
};

/**
 * Utility methods for detecting TouchID & using it
 */
@interface TouchIDHelper : NSObject

+ (BOOL) touchIDAvailable;

+ (void)authenticateViaPasswordOrTouchIDCompletion:(void(^)(TSTouchIDAuthResult result))completion;
@end
