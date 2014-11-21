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

-(TSRequest*) initWithRecipient:(NSString*)recipientNumber {
  NSString* recipientInformation = recipientNumber;
  
  self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/*", textSecureKeysAPI, recipientInformation]]];
    
  [self setHTTPMethod:@"GET"];
  
  return self;
}

@end
