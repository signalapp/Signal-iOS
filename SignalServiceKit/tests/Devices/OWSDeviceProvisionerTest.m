//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDeviceProvisioner.h"
#import "OWSDeviceProvisioningCodeService.h"
#import "OWSDeviceProvisioningService.h"
#import "OWSFakeNetworkManager.h"
#import "SSKBaseTestObjC.h"
#import "TSNetworkManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSFakeDeviceProvisioningService : OWSDeviceProvisioningService

@end

@implementation OWSFakeDeviceProvisioningService

- (void)provisionWithMessageBody:(NSData *)messageBody
               ephemeralDeviceId:(NSString *)deviceId
                         success:(void (^)(void))successCallback
                         failure:(void (^)(NSError *))failureCallback
{
    OWSLogInfo(@"faking successful provisioning");
    successCallback();
}

@end

@interface OWSFakeDeviceProvisioningCodeService : OWSDeviceProvisioningCodeService

@end

@implementation OWSFakeDeviceProvisioningCodeService

- (void)requestProvisioningCodeWithSuccess:(void (^)(NSString *))successCallback
                                   failure:(void (^)(NSError *))failureCallback
{
    OWSLogInfo(@"faking successful provisioning code fetching");
    successCallback(@"fake-provisioning-code");
}

@end

@interface OWSDeviceProvisioner (Testing)

@property OWSDeviceProvisioningCodeService *provisioningCodeService;
@property OWSDeviceProvisioningService *provisioningService;

@end

@interface OWSDeviceProvisionerTest : SSKBaseTestObjC

@end

@implementation OWSDeviceProvisionerTest

- (void)testProvisioning
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Provisioning Success"];

    NSData *nullKey = [[NSMutableData dataWithLength:32] copy];
    NSData *myPublicKey = [nullKey copy];
    NSData *myPrivateKey = [nullKey copy];
    NSData *theirPublicKey = [nullKey copy];
    NSData *profileKey = [nullKey copy];
    SignalServiceAddress *accountAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:@"13213214321"];
    NSString *theirEphemeralDeviceId;

    OWSFakeNetworkManager *networkManager = [[OWSFakeNetworkManager alloc] init];

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc]
            initWithMyPublicKey:myPublicKey
                   myPrivateKey:myPrivateKey
                 theirPublicKey:theirPublicKey
         theirEphemeralDeviceId:theirEphemeralDeviceId
                 accountAddress:accountAddress
                     profileKey:profileKey
            readReceiptsEnabled:YES
        provisioningCodeService:[[OWSFakeDeviceProvisioningCodeService alloc] initWithNetworkManager:networkManager]
            provisioningService:[[OWSFakeDeviceProvisioningService alloc] initWithNetworkManager:networkManager]];

    [provisioner
        provisionWithSuccess:^{
            [expectation fulfill];
        }
        failure:^(NSError *_Nonnull error) {
            XCTAssert(NO, @"Failed to provision with error: %@", error);
        }];

    [self waitForExpectationsWithTimeout:5.0
                                 handler:^(NSError *error) {
                                     if (error) {
                                         OWSLogInfo(@"Timeout Error: %@", error);
                                     }
                                 }];
}

@end
