//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDevicesService.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSDevice.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import <Mantle/MTLJSONAdapter.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const NSNotificationNameDeviceListUpdateSucceeded = @"NSNotificationNameDeviceListUpdateSucceeded";
NSNotificationName const NSNotificationNameDeviceListUpdateFailed = @"NSNotificationNameDeviceListUpdateFailed";
NSNotificationName const NSNotificationNameDeviceListUpdateModifiedDeviceList
    = @"NSNotificationNameDeviceListUpdateModifiedDeviceList";

@implementation OWSDevicesService

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (void)refreshDevices
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self
            getDevicesWithSuccess:^(NSArray<OWSDevice *> *devices) {
                // If we have more than one device; we may have a linked device.
                if (devices.count > 1) {
                    // Setting this flag here shouldn't be necessary, but we do so
                    // because the "cost" is low and it will improve robustness.
                    [OWSDeviceManager.shared setMayHaveLinkedDevices];
                }

                __block BOOL didAddOrRemove;
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    didAddOrRemove = [OWSDevice replaceAll:devices transaction:transaction];
                });

                [NSNotificationCenter.defaultCenter
                    postNotificationNameAsync:NSNotificationNameDeviceListUpdateSucceeded
                                       object:nil];

                if (didAddOrRemove) {
                    [NSNotificationCenter.defaultCenter
                        postNotificationNameAsync:NSNotificationNameDeviceListUpdateModifiedDeviceList
                                           object:nil];
                }
            }
            failure:^(NSError *error) {
                OWSLogError(@"Request device list failed with error: %@", error);

                [NSNotificationCenter.defaultCenter postNotificationNameAsync:NSNotificationNameDeviceListUpdateFailed
                                                                       object:error];
            }];
    });
}

+ (void)getDevicesWithSuccess:(void (^)(NSArray<OWSDevice *> *))successCallback
                      failure:(void (^)(NSError *))failureCallback
{
    TSRequest *request = [OWSRequestFactory getDevicesRequest];
    [[TSNetworkManager shared] makeRequest:request
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
            if (!IsNetworkConnectivityFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorGetDevicesFailed]);
            }
            OWSLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

+ (void)unlinkDevice:(OWSDevice *)device
             success:(void (^)(void))successCallback
             failure:(void (^)(NSError *))failureCallback
{
    TSRequest *request = [OWSRequestFactory deleteDeviceRequestWithDevice:device];

    [[TSNetworkManager shared] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSLogVerbose(@"Delete device request succeeded");
            successCallback();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNetworkConnectivityFailure(error)) {
                OWSProdError([OWSAnalyticsEvents errorUnlinkDeviceFailed]);
            }
            OWSLogVerbose(@"Get devices request failed with error: %@", error);
            failureCallback(error);
        }];
}

+ (NSArray<OWSDevice *> *)parseResponse:(id)responseObject
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
