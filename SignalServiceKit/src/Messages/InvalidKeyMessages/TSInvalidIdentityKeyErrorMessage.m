//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>

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

- (void)acceptNewIdentityKeyWithError:(NSError **)error
{
    @try {
        [self throws_acceptNewIdentityKey];
    } @catch (NSException *exception) {
        *error = OWSErrorMakeAssertionError(@"Error: %@", exception.debugDescription);
    }
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

@end

NS_ASSUME_NONNULL_END
