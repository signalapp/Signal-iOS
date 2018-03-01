//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSContactsIntersectionRequest.h"
#import "TSConstants.h"

@implementation TSContactsIntersectionRequest

- (id)initWithHashesArray:(NSArray *)hashes {
    self = [self
        initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureDirectoryAPI, @"tokens"]]];

    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"PUT";

    self.parameters = @{
        @"contacts" : hashes,
    };

    return self;
}

@end
