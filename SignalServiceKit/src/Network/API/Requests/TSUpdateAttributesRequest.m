//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttributes.h"
#import "TSConstants.h"
#import "TSUpdateAttributesRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSUpdateAttributesRequest

- (instancetype)initWithManualMessageFetching:(BOOL)enableManualMessageFetching
{
    NSString *endPoint = [textSecureAccountsAPI stringByAppendingString:textSecureAttributesAPI];
    self = [super initWithURL:[NSURL URLWithString:endPoint]];

    if (self) {
        [self setHTTPMethod:@"PUT"];
        [self.parameters addEntriesFromDictionary:[TSAttributes attributesFromStorageWithManualMessageFetching:enableManualMessageFetching]];
    }
    
    return self;
}

@end

NS_ASSUME_NONNULL_END
