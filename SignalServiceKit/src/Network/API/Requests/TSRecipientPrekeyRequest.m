//
//  TSGetRecipientPrekey.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 11/30/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRecipientPrekeyRequest.h"

@implementation TSRecipientPrekeyRequest

- (TSRequest *)initWithRecipient:(NSString *)recipientNumber deviceId:(NSString *)deviceId {
    NSString *recipientInformation = recipientNumber;

    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/%@",
                                                                              textSecureKeysAPI,
                                                                              recipientInformation,
                                                                              deviceId]]];

    self.HTTPMethod = @"GET";
    self.parameters = nil;

    return self;
}

@end
