//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWS103EnableVideoCalling.h"
#import <SignalServiceKit/TSUpdateAttributesRequest.h>
#import <SignalServiceKit/TSNetworkManager.h>

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

    TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc] initWithUpdatedAttributesWithVoice];
    [[TSNetworkManager sharedManager] makeRequest:request
                                          success:^(NSURLSessionDataTask *task, id responseObject) {
                                              DDLogInfo(@"%@ successfully ran", self.tag);
                                              [self save];
                                          }
                                          failure:^(NSURLSessionDataTask *task, NSError *error) {
                                              DDLogError(@"%@ failed with error: %@", self.tag, error);
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
