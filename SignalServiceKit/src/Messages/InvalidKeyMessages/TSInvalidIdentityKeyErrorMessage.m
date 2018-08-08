//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)acceptNewIdentityKey
{
    OWS_ABSTRACT_METHOD();
}

- (nullable NSData *)newIdentityKey
{
    OWS_ABSTRACT_METHOD();
    return nil;
}

- (NSString *)theirSignalId
{
    OWS_ABSTRACT_METHOD();
    return nil;
}

@end

NS_ASSUME_NONNULL_END
