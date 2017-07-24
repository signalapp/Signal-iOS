//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWS103EnableVideoCalling.h"
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSUpdateAttributesRequest.h>

// Increment a similar constant for every future DBMigration
static NSString *const OWS103EnableVideoCallingMigrationId = @"103";

@implementation OWS103EnableVideoCalling

+ (NSString *)migrationId
{
    return OWS103EnableVideoCallingMigrationId;
}

// Override parent migration
- (void)runUp
{
    DDLogWarn(@"%@ running migration...", self.tag);

    // TODO: It'd be nice if TSAccountManager had a
    //       [ifRegisteredRunAsync: ifNoRegisteredRunAsync:] method.
    [[TSAccountManager sharedInstance] ifRegistered:YES
                                           runAsync:^{
                                               TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc]
                                                   initWithUpdatedAttributesWithVoice];
                                               [[TSNetworkManager sharedManager] makeRequest:request
                                                   success:^(NSURLSessionDataTask *task, id responseObject) {
                                                       DDLogInfo(@"%@ successfully ran", self.tag);
                                                       [self save];
                                                   }
                                                   failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                       if (!IsNSErrorNetworkFailure(error)) {
                                                           OWSProdErrorWNSError(
                                                               @"error_enable_video_calling_request_failed", error);
                                                       }
                                                       DDLogError(@"%@ failed with error: %@", self.tag, error);
                                                   }];
                                           }];
    [[TSAccountManager sharedInstance] ifRegistered:NO
                                           runAsync:^{
                                               DDLogInfo(@"%@ skipping; not registered", self.tag);
                                               [self save];
                                           }];
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
