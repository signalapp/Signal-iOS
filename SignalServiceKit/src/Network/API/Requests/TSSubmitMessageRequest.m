//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSSubmitMessageRequest.h"
#import "TSConstants.h"

@implementation TSSubmitMessageRequest

- (TSRequest *)initWithRecipient:(NSString *)contactRegisteredID
                        messages:(NSArray *)messages
                           relay:(NSString *)relay
                       timeStamp:(uint64_t)timeStamp {
    self =
        [super initWithURL:[NSURL URLWithString:[textSecureMessagesAPI stringByAppendingString:contactRegisteredID]]];
    if (!self) {
        return nil;
    }

    NSMutableDictionary *parameters = [@{
        @"messages" : messages,
        @"timestamp" : @(timeStamp),
    } mutableCopy];

    if (relay) {
        parameters[@"relay"] = relay;
    }

    [self setHTTPMethod:@"PUT"];
    self.parameters = parameters;
    return self;
}

@end
