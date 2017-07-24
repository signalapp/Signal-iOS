//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDevicesService.h"
#import "OWSDeleteDeviceRequest.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSGetDevicesRequest.h"
#import "TSNetworkManager.h"
#import <Mantle/MTLJSONAdapter.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDevicesService

- (void)getDevicesWithSuccess:(void (^)(NSArray<OWSDevice *> *))successCallback
                      failure:(void (^)(NSError *))failureCallback
{
    OWSGetDevicesRequest *request = [OWSGetDevicesRequest new];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogVerbose(@"Get devices request succeeded");
            NSArray<OWSDevice *> *devices = [self parseResponse:responseObject];

            if (devices) {
                successCallback(devices);
            } else {
                DDLogError(@"%@ unable to parse devices response:%@", self.tag, responseObject);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                failureCallback(error);
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdErrorWNSError(@"error_get_devices_failed", error);
            }
            DDLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

- (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)())successCallback
             failure:(void (^)(NSError *))failureCallback
{
    OWSDeleteDeviceRequest *request = [[OWSDeleteDeviceRequest alloc] initWithDevice:device];

    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogVerbose(@"Delete device request succeeded");
            successCallback();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdErrorWNSError(@"error_unlink_device_failed", error);
            }
            DDLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

- (NSArray<OWSDevice *> *)parseResponse:(id)responseObject
{
    if (![responseObject isKindOfClass:[NSDictionary class]]) {
        DDLogError(@"Device response was not a dictionary.");
        return nil;
    }
    NSDictionary *response = (NSDictionary *)responseObject;

    NSArray<NSDictionary *> *devicesAttributes = response[@"devices"];
    if (!devicesAttributes) {
        DDLogError(@"Device response had no devices.");
        return nil;
    }

    NSMutableArray<OWSDevice *> *devices = [NSMutableArray new];
    for (NSDictionary *deviceAttributes in devicesAttributes) {
        NSError *error;
        OWSDevice *device = [OWSDevice deviceFromJSONDictionary:deviceAttributes error:&error];
        if (error) {
            DDLogError(@"Failed to build device from dictionary with error: %@", error);
        } else {
            [devices addObject:device];
        }
    }

    return [devices copy];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
