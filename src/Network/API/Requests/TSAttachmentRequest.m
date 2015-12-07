//
//  TSRequestAttachment.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/1/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentRequest.h"
#import "TSConstants.h"

@implementation TSAttachmentRequest

- (TSRequest *)initWithId:(NSNumber *)attachmentId relay:(NSString *)relay {
    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAttachmentsAPI, attachmentId];

    if (relay && ![relay isEqualToString:@""]) {
        path = [path stringByAppendingFormat:@"?relay=%@", relay];
    }

    self = [super initWithURL:[NSURL URLWithString:path]];

    self.HTTPMethod = @"GET";
    return self;
}

@end
