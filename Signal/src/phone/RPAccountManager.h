//
//  RPAccountManager.h
//  Signal
//
//  Created by Frederic Jacobs on 19/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RPAccountManager : NSObject

+ (void)registrationWithTsToken:(NSString *)tsToken
                      pushToken:(NSString *)pushToken
                      voipToken:(NSString *)voipPushToken
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure;

@end
