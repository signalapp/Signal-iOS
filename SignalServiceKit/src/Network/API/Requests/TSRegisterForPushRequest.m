//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRegisterForPushRequest.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSRegisterForPushRequest

- (id)initWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId {
    self =
        [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"]]];

    if (!self) {
        return nil;
    }

    self.HTTPMethod = @"PUT";

    OWSAssert(voipId);
    self.parameters = @{
        @"apnRegistrationId" : identifier,
        @"voipRegistrationId" : voipId ?: @"",
    };

    return self;
}

@end

NS_ASSUME_NONNULL_END
