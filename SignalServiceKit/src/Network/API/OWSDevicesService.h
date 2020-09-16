//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NSNotificationNameDeviceListUpdateSucceeded;
extern NSNotificationName const NSNotificationNameDeviceListUpdateFailed;
extern NSNotificationName const NSNotificationNameDeviceListUpdateModifiedDeviceList;

@class OWSDevice;

@interface OWSDevicesService : NSObject

+ (void)refreshDevices;

+ (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)(void))successCallback
             failure:(void (^)(NSError *))failureCallback;

@end

NS_ASSUME_NONNULL_END
