//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)try_acceptNewIdentityKey
{
    OWSAbstractMethod();
}

- (nullable NSData *)try_newIdentityKey
{
    OWSAbstractMethod();
    return nil;
}

- (NSString *)theirSignalId
{
    OWSAbstractMethod();
    return nil;
}

@end

NS_ASSUME_NONNULL_END
