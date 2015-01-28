//
//  TSCurrentSignedPreKeyRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 27/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSCurrentSignedPreKeyRequest.h"
#import "TSConstants.h"

@implementation TSCurrentSignedPreKeyRequest

- (instancetype)init {
    self = [super initWithURL:[NSURL URLWithString:textSecureSignedKeysAPI]];
    
    self.HTTPMethod = @"GET";
    
    return self;
}

@end
