//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)acceptNewIdentityKey
{
    OWSFailNoProdLog(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
}

- (nullable NSData *)newIdentityKey
{
    OWSFailNoProdLog(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

- (NSString *)theirSignalId
{
    OWSFailNoProdLog(@"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

@end

NS_ASSUME_NONNULL_END
