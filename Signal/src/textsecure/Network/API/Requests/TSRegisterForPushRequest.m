//
//  TSRegisterForPushRequest.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/13/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

#import "TSRegisterForPushRequest.h"

@implementation TSRegisterForPushRequest

- (id) initWithPushIdentifier:(NSString*)identifier voipIdentifier:(NSString*)voipId
{
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"]]];
    
    self.HTTPMethod = @"PUT";
    
    self.parameters = [NSMutableDictionary dictionaryWithObjects:@[identifier, voipId] forKeys:@[@"apnRegistrationId", @"voipRegistrationId"]];
    
    return self;
}

@end
