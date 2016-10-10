//
//  RPAccountManager.h
//  Signal
//
//  Created by Frederic Jacobs on 19/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface RPAccountManager : NSObject

+ (instancetype)sharedInstance;

- (void)registerWithTsToken:(NSString *)tsToken
                    success:(void (^)())success
                    failure:(void (^)(NSError *))failure;

/**
 *  Register's the device's push notification token with the server
 *
 *  @param pushToken Apple's Push Token
 */
- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)())successHandler
                                          failure:(void (^)(NSError *error))failureHandler
    NS_SWIFT_NAME(registerForPushNotifications(pushToken:voipToken:success:failure:));

@end

NS_ASSUME_NONNULL_END
