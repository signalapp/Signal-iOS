//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRegisterForPushRequest.h"
#import "TSConstants.h"

@implementation TSRegisterForPushRequest

- (id)initWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId {
    self =
        [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"]]];

    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"PUT";

    NSMutableDictionary *parameters = [@{ @"apnRegistrationId" : identifier } mutableCopy];

    if (voipId) {
        parameters[@"voipRegistrationId"] = voipId;
    }

    self.parameters = parameters;

    return self;
}

@end
