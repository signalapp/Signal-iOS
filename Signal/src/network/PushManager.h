//
//  PushManager.h
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PushManager : NSObject

+ (instancetype)sharedManager;


- (void)verifyPushActivated;

- (void)askForPushRegistration;

- (void)registerForPushWithToken:(NSData*)token;

@end

