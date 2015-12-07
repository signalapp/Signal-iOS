//
//  TSContactsIntersection.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/12/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

#import "TSContactsIntersectionRequest.h"

@implementation TSContactsIntersectionRequest

- (id)initWithHashesArray:(NSArray *)hashes {
    self = [self
        initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureDirectoryAPI, @"tokens"]]];

    self.HTTPMethod = @"PUT";

    [self.parameters addEntriesFromDictionary:@{ @"contacts" : hashes }];

    return self;
}

@end
