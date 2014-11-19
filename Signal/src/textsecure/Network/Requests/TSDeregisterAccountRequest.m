//
//  TSDeregisterAccountRequest.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 3/16/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSDeregisterAccountRequest.h"

@implementation TSDeregisterAccountRequest


- (id)initWithUser:(NSString*)userPushId {
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"]]];
    self.HTTPMethod = @"DELETE";
    self.parameters = [NSMutableDictionary dictionaryWithObjects:@[userPushId] forKeys:@[@"apnRegistrationId"]];
    return self;
    
}
@end
