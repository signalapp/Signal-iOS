//
//  TSCurrentSignedPreKeyRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 27/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSCurrentSignedPreKeyRequest.h"

@implementation TSCurrentSignedPreKeyRequest

- (instancetype)init {
    self = [super initWithURL:[NSURL URLWithString:textSecureSignedKeysAPI]];

    self.HTTPMethod = @"GET";

    return self;
}

@end
