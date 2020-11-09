//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSNetworkManager;

@interface OWSDeviceProvisioningCodeService : NSObject

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager NS_DESIGNATED_INITIALIZER;

- (void)requestProvisioningCodeWithSuccess:(void (^)(NSString *))successCallback
                                   failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
