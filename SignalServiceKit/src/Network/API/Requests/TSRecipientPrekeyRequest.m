//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRecipientPrekeyRequest.h"
#import "TSConstants.h"

@implementation TSRecipientPrekeyRequest

- (TSRequest *)initWithRecipient:(NSString *)recipientNumber deviceId:(NSString *)deviceId {
    self = [super
        initWithURL:[NSURL
                        URLWithString:[NSString
                                          stringWithFormat:@"%@/%@/%@", textSecureKeysAPI, recipientNumber, deviceId]]];

    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"GET";
    self.parameters = nil;

    return self;
}

@end
