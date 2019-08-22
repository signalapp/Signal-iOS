//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)throws_acceptNewIdentityKey
{
    OWSAbstractMethod();
}

- (nullable NSData *)throws_newIdentityKey
{
    OWSAbstractMethod();
    return nil;
}

- (SignalServiceAddress *)theirSignalAddress
{
    OWSAbstractMethod();
    return nil;
}

- (BOOL)isSpecialMessage
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
