//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSUpdateAttributesRequest.h"
#import "TSAttributes.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSUpdateAttributesRequest

- (instancetype)initWithManualMessageFetching:(BOOL)enableManualMessageFetching
{
    NSString *endPoint = [textSecureAccountsAPI stringByAppendingString:textSecureAttributesAPI];
    self = [super initWithURL:[NSURL URLWithString:endPoint]];

    if (self) {
        [self setHTTPMethod:@"PUT"];
        self.parameters = [TSAttributes attributesFromStorageWithManualMessageFetching:enableManualMessageFetching];
    }
    
    return self;
}

@end

NS_ASSUME_NONNULL_END
