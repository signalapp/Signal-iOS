//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TSNetworkManager;

@interface OWSDeviceProvisioningService : NSObject

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager;

- (void)provisionWithMessageBody:(NSData *)messageBody
               ephemeralDeviceId:(NSString *)deviceId
                         success:(void (^)(void))successCallback
                         failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
