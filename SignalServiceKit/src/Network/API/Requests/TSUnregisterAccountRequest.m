//
//  TSDeregisterAccountRequest.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 3/16/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSUnregisterAccountRequest.h"

@implementation TSUnregisterAccountRequest


- (id)init {
    self =
        [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"]]];
    self.HTTPMethod = @"DELETE";
    return self;
}
@end
