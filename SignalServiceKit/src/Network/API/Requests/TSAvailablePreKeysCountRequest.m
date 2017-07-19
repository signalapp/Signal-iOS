//
//  TSAvailablePreKeysCountRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 27/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSAvailablePreKeysCountRequest.h"

#import "TSConstants.h"

@implementation TSAvailablePreKeysCountRequest

- (instancetype)init {
    NSString *path = [NSString stringWithFormat:@"%@", textSecureKeysAPI];

    self = [super initWithURL:[NSURL URLWithString:path]];

    if (self) {
        [self setHTTPMethod:@"GET"];
    }

    return self;
}

@end
