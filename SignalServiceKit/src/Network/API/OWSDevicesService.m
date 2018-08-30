//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDevicesService.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import <Mantle/MTLJSONAdapter.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDevicesService

- (void)getDevicesWithSuccess:(void (^)(NSArray<OWSDevice *> *))successCallback
                      failure:(void (^)(NSError *))failureCallback
{
    TSRequest *request = [OWSRequestFactory getDevicesRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSLogVerbose(@"Get devices request succeeded");
            NSArray<OWSDevice *> *devices = [self parseResponse:responseObject];

            if (devices) {
                successCallback(devices);
            } else {
                OWSLogError(@"unable to parse devices response:%@", responseObject);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                failureCallback(error);
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorGetDevicesFailed]);
            }
            OWSLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

- (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)(void))successCallback
             failure:(void (^)(NSError *))failureCallback
{
    TSRequest *request = [OWSRequestFactory deleteDeviceRequestWithDevice:device];

    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSLogVerbose(@"Delete device request succeeded");
            successCallback();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorUnlinkDeviceFailed]);
            }
            OWSLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

- (NSArray<OWSDevice *> *)parseResponse:(id)responseObject
{
    if (![responseObject isKindOfClass:[NSDictionary class]]) {
        OWSLogError(@"Device response was not a dictionary.");
        return nil;
    }
    NSDictionary *response = (NSDictionary *)responseObject;

    NSArray<NSDictionary *> *devicesAttributes = response[@"devices"];
    if (!devicesAttributes) {
        OWSLogError(@"Device response had no devices.");
        return nil;
    }

    NSMutableArray<OWSDevice *> *devices = [NSMutableArray new];
    for (NSDictionary *deviceAttributes in devicesAttributes) {
        NSError *error;
        OWSDevice *_Nullable device = [OWSDevice deviceFromJSONDictionary:deviceAttributes error:&error];
        if (error || !device) {
            OWSLogError(@"Failed to build device from dictionary with error: %@", error);
        } else {
            [devices addObject:device];
        }
    }

    return [devices copy];
}

@end

NS_ASSUME_NONNULL_END
