//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSGetProfileRequest.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGetProfileRequest

- (instancetype)initWithRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    NSString *path = [NSString stringWithFormat:textSecureProfileAPIFormat, recipientId];
    self = [super initWithURL:[NSURL URLWithString:path]];
    if (!self) {
        return self;
    }
    
    self.HTTPMethod = @"GET";
    self.parameters = nil;
    
    return self;
}

@end

NS_ASSUME_NONNULL_END
