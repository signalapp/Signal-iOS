//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)acceptNewIdentityKey
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
}

- (NSString *)newIdentityKey
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

- (NSString *)theirSignalId
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

@end

NS_ASSUME_NONNULL_END
