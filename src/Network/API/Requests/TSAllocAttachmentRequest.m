//
//  TSAllocAttachmentRequest.m
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAllocAttachmentRequest.h"
#import "TSConstants.h"

@implementation TSAllocAttachmentRequest

- (instancetype)init {
    NSString *path = [NSString stringWithFormat:@"%@", textSecureAttachmentsAPI];

    self = [super initWithURL:[NSURL URLWithString:path]];

    if (self) {
        [self setHTTPMethod:@"GET"];
    }

    return self;
}

@end
