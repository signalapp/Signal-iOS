//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

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
