//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)acceptNewIdentityKey
{
    OWSFail(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
}

- (nullable NSData *)newIdentityKey
{
    OWSFail(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

- (NSString *)theirSignalId
{
    OWSFail(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

@end

NS_ASSUME_NONNULL_END
