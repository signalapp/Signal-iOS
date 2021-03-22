//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWS103EnableVideoCalling.h"
#import <SignalServiceKit/OWSRequestFactory.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSNetworkManager.h>

// Increment a similar constant for every future DBMigration
static NSString *const OWS103EnableVideoCallingMigrationId = @"103";

@implementation OWS103EnableVideoCalling

+ (NSString *)migrationId
{
    return OWS103EnableVideoCallingMigrationId;
}

// Override parent migration
- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssertDebug(completion);

    OWSLogWarn(@"running migration...");
    if ([self.tsAccountManager isRegistered]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TSRequest *request = [OWSRequestFactory updatePrimaryDeviceAttributesRequest];
            [[TSNetworkManager shared] makeRequest:request
                success:^(NSURLSessionDataTask *task, id responseObject) {
                    OWSLogInfo(@"successfully ran");
                    [self markAsCompleteWithSneakyTransaction];

                    completion();
                }
                failure:^(NSURLSessionDataTask *task, NSError *error) {
                    if (!IsNetworkConnectivityFailure(error)) {
                        OWSProdError([OWSAnalyticsEvents errorEnableVideoCallingRequestFailed]);
                    }
                    OWSLogError(@"failed with error: %@", error);

                    completion();
                }];
        });
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            OWSLogInfo(@"skipping; not registered");
            [self markAsCompleteWithSneakyTransaction];

            completion();
        });
    }
}

@end
