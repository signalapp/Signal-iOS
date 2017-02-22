//
//  TSUpdateAttributesRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 22/08/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"
#import "TSConstants.h"
#import "TSUpdateAttributesRequest.h"

@implementation TSUpdateAttributesRequest

- (instancetype)initWithUpdatedAttributesWithVoice {
    NSString *endPoint = [textSecureAccountsAPI stringByAppendingString:textSecureAttributesAPI];
    self               = [super initWithURL:[NSURL URLWithString:endPoint]];

    if (self) {
        [self setHTTPMethod:@"PUT"];
        [self.parameters addEntriesFromDictionary:[TSAttributes attributesFromStorageWithVoiceSupport]];
    }

    return self;
}

@end
