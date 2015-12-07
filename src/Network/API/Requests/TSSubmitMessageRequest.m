//
//  TSSubmitMessageRequest.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 11/30/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

#import "TSSubmitMessageRequest.h"

@implementation TSSubmitMessageRequest

- (TSRequest *)initWithRecipient:(NSString *)contactRegisteredID
                        messages:(NSArray *)messages
                           relay:(NSString *)relay
                       timeStamp:(uint64_t)timeStamp {
    self =
        [super initWithURL:[NSURL URLWithString:[textSecureMessagesAPI stringByAppendingString:contactRegisteredID]]];

    NSMutableDictionary *allMessages =
        [@{ @"messages" : messages,
            @"timestamp" : [NSNumber numberWithUnsignedLongLong:timeStamp] } mutableCopy];

    if (relay) {
        [allMessages setObject:relay forKey:@"relay"];
    }

    [self setHTTPMethod:@"PUT"];
    [self setParameters:allMessages];
    return self;
}

@end
