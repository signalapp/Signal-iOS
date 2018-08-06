//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSDevice;

@interface OWSDevicesService : NSObject

- (void)getDevicesWithSuccess:(void (^)(NSArray<OWSDevice *> *))successCallback
                      failure:(void (^)(NSError *))failureCallback;

- (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)(void))successCallback
             failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
